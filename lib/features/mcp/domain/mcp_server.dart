import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';

/// A tool the agent can call.
class McpTool {
  final String name;
  final String description;

  /// JSON Schema of the arguments.
  final Map<String, dynamic> inputSchema;

  /// Returns JSON-encodable data, shown to the agent as text.
  final Future<Object?> Function(Map<String, dynamic> arguments) handler;

  /// False for tools that only read.
  final bool writes;

  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.writes = false,
  });
}

/// An error a tool reports to the agent as a tool result with isError.
class McpToolError implements Exception {
  final String message;

  McpToolError(this.message);

  @override
  String toString() => message;
}

/// A minimal Model Context Protocol server over the Streamable HTTP
/// transport (JSON responses only, no server-initiated messages), running
/// inside the app so any MCP client on the same network can reach it.
///
/// Every request needs `Authorization: Bearer <token>`. Tools are supplied
/// by the caller; write tools are expected to queue proposals that the user
/// approves in the app rather than change data directly.
class McpServer {
  static const protocolVersion = '2025-06-18';
  static const path = '/mcp';

  final _log = Logger('McpServer');
  final String serverName;
  final String serverVersion;
  final String token;
  final List<McpTool> Function() tools;

  HttpServer? _server;

  McpServer({
    required this.token,
    required this.tools,
    this.serverName = 'eatpoint',
    this.serverVersion = '1.0.0',
  });

  static String generateToken() {
    final random = Random.secure();
    return base64UrlEncode(
      List.generate(24, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  /// Starts listening on every interface on [port] (0 = any free port).
  Future<int> start({int port = 8765, InternetAddress? address}) async {
    await stop();
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    _server = server;
    server.listen(_handle, onError: (Object e) => _log.warning('$e'));
    _log.info('MCP server on port ${server.port}');
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != path) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth == null || auth != 'Bearer $token') {
        response.statusCode = HttpStatus.unauthorized;
        return;
      }
      if (request.method == 'DELETE') {
        response.statusCode = HttpStatus.ok;
        return;
      }
      if (request.method != 'POST') {
        // No server-to-client stream is offered.
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'POST, DELETE');
        return;
      }
      final body = await utf8.decodeStream(request);
      final Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        _writeJson(response, _error(null, -32700, 'Parse error'));
        return;
      }
      if (decoded is List) {
        final results = <Object>[];
        for (final message in decoded) {
          final result = await handleMessage(message);
          if (result != null) results.add(result);
        }
        if (results.isEmpty) {
          response.statusCode = HttpStatus.accepted;
        } else {
          _writeJson(response, results);
        }
        return;
      }
      final result = await handleMessage(decoded);
      if (result == null) {
        response.statusCode = HttpStatus.accepted;
      } else {
        _writeJson(response, result);
      }
    } catch (e, st) {
      _log.warning('MCP request failed: $e', e, st);
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  void _writeJson(HttpResponse response, Object json) {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(json));
  }

  /// Handles one JSON-RPC message. Returns null for notifications.
  Future<Map<String, dynamic>?> handleMessage(Object? message) async {
    if (message is! Map) return _error(null, -32600, 'Invalid Request');
    final id = message['id'];
    final method = message['method'];
    final params = message['params'];
    final isNotification = !message.containsKey('id');
    if (method is! String) {
      return isNotification ? null : _error(id, -32600, 'Invalid Request');
    }
    switch (method) {
      case 'initialize':
        return _result(id, {
          'protocolVersion': protocolVersion,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': serverName, 'version': serverVersion},
          'instructions':
              'EatPoint is a points-based nutrition tracker. One point is '
              '100 kcal of one macronutrient (carbs, protein or fat). Read '
              'tools return the user\'s menus, shopping list and budget. '
              'Write tools only create proposals: the user approves each one '
              'in the app.',
        });
      case 'ping':
        return _result(id, {});
      case 'tools/list':
        return _result(id, {
          'tools': [
            for (final tool in tools())
              {
                'name': tool.name,
                'description': tool.description,
                'inputSchema': tool.inputSchema,
                'annotations': {'readOnlyHint': !tool.writes},
              },
          ],
        });
      case 'tools/call':
        if (params is! Map || params['name'] is! String) {
          return _error(id, -32602, 'Invalid params');
        }
        final name = params['name'] as String;
        final tool = tools().where((t) => t.name == name).firstOrNull;
        if (tool == null) return _error(id, -32602, 'Unknown tool: $name');
        final rawArgs = params['arguments'];
        final args = rawArgs is Map
            ? Map<String, dynamic>.from(rawArgs)
            : <String, dynamic>{};
        try {
          final data = await tool.handler(args);
          return _result(id, {
            'content': [
              {
                'type': 'text',
                'text': const JsonEncoder.withIndent('  ').convert(data),
              },
            ],
            'isError': false,
          });
        } on McpToolError catch (e) {
          return _result(id, {
            'content': [
              {'type': 'text', 'text': e.message},
            ],
            'isError': true,
          });
        }
      default:
        if (method.startsWith('notifications/')) return null;
        return isNotification
            ? null
            : _error(id, -32601, 'Method not found: $method');
    }
  }

  static Map<String, dynamic> _result(Object? id, Object result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, dynamic> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}
