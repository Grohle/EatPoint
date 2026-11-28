import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/gemini_endpoint.dart';

/// EatPoint: keeps requests to Google's Gemini API from hanging.
///
/// `gemini-flash-latest` follows Google's newest Flash model, and on the
/// free tier a model that new is often overloaded: Google answers 503
/// ("high demand") or, worse, holds the connection open with no answer until
/// the app gives up. So a request to Gemini that is refused as busy, rate
/// limited or unknown (a retired model), or that has no answer after
/// [attemptTimeout], is cancelled and sent again with the next model of
/// [fallbacks]. The last one gets the rest of the caller's time.
///
/// Gemini's Flash models think before answering, and the thinking counts
/// against `max_tokens`: with the app's small budgets the answer came back
/// cut off. Each request asks for minimal thinking (resent without it if a
/// model refuses the setting) and gets room for at least [minTokens].
///
/// Any other request passes through untouched.
class GeminiFallbackClient extends http.BaseClient {
  /// Google's newest Flash first, then an older Flash that is less in
  /// demand, then the light ones, which nearly always answer but read less
  /// carefully. A version Google has retired answers 404 and is skipped;
  /// the aliases never need updating.
  static const fallbacks = [
    'gemini-flash-latest',
    'gemini-3.5-flash',
    'gemini-flash-lite-latest',
    'gemini-3.5-flash-lite',
  ];

  /// How long one model gets to start answering before the next is tried.
  static const defaultAttemptTimeout = Duration(seconds: 20);

  /// The smallest answer budget a request to Gemini gets.
  static const minTokens = 2048;

  /// Statuses that say "try another model", not "your request is wrong".
  static const _retryable = {404, 429, 500, 502, 503, 504};

  final _log = Logger('GeminiFallbackClient');
  final http.Client _inner;
  final Duration attemptTimeout;

  GeminiFallbackClient(
    this._inner, {
    this.attemptTimeout = defaultAttemptTimeout,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request ||
        request.method != 'POST' ||
        !isGeminiEndpoint(request.url)) {
      return _inner.send(request);
    }
    final Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(request.body);
      if (decoded is! Map<String, dynamic>) return _inner.send(request);
      body = decoded;
    } on FormatException {
      return _inner.send(request);
    }
    final first = body['model'];
    final models = <String>[
      if (first is String && first.isNotEmpty) first,
      for (final m in fallbacks)
        if (m != first) m,
    ];

    final tokens = body['max_tokens'];
    final tuned = <String, dynamic>{
      ...body,
      if (tokens is! num || tokens < minTokens) 'max_tokens': minTokens,
      'reasoning_effort': body['reasoning_effort'] ?? 'minimal',
    };
    final addedEffort = body['reasoning_effort'] == null;

    for (var i = 0; i < models.length; i++) {
      final last = i == models.length - 1;
      try {
        var response = await _attempt(request, {
          ...tuned,
          'model': models[i],
        }, last: last);
        // A model that doesn't take the thinking setting: same model,
        // without it.
        if (response.statusCode == 400 && addedEffort) {
          await response.stream.drain<void>();
          response = await _attempt(
            request,
            {...tuned, 'model': models[i]}..remove('reasoning_effort'),
            last: last,
          );
        }
        if (!last && _retryable.contains(response.statusCode)) {
          _log.info(
            'Gemini ${models[i]} answered ${response.statusCode}; '
            'trying ${models[i + 1]}',
          );
          await response.stream.drain<void>();
          continue;
        }
        return response;
      } on TimeoutException {
        _log.info(
          'Gemini ${models[i]} gave no answer in '
          '${attemptTimeout.inSeconds}s; trying ${models[i + 1]}',
        );
      }
    }
    // Not reached: the last attempt returns or throws.
    throw StateError('no Gemini model left to try');
  }

  /// Sends [body] like [original]; unless it is the [last] attempt, gives up
  /// (and cancels it) after [attemptTimeout].
  Future<http.StreamedResponse> _attempt(
    http.Request original,
    Map<String, dynamic> body, {
    required bool last,
  }) async {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('POST', original.url, abortTrigger: abort.future)
          ..headers.addAll(original.headers)
          ..followRedirects = original.followRedirects
          ..body = jsonEncode(body);
    final pending = _inner.send(request);
    if (last) return pending;
    try {
      return await pending.timeout(attemptTimeout);
    } on TimeoutException {
      abort.complete();
      rethrow;
    }
  }
}

/// [client], with [GeminiFallbackClient] in front when [endpoint] is
/// Google's Gemini API.
http.Client withGeminiFallback(http.Client client, Uri? endpoint) =>
    endpoint != null && isGeminiEndpoint(endpoint)
    ? GeminiFallbackClient(client)
    : client;
