import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/mcp/domain/mcp_server.dart';

void main() {
  const token = 'secret-token';
  late McpServer server;
  late Uri url;

  setUp(() async {
    server = McpServer(
      token: token,
      tools: () => [
        McpTool(
          name: 'echo',
          description: 'Echoes',
          inputSchema: const {'type': 'object', 'properties': {}},
          handler: (args) async => {'echo': args['text']},
        ),
        McpTool(
          name: 'boom',
          description: 'Fails',
          writes: true,
          inputSchema: const {'type': 'object', 'properties': {}},
          handler: (_) async => throw McpToolError('nope'),
        ),
      ],
    );
    final port = await server.start(
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    url = Uri.parse('http://127.0.0.1:$port/mcp');
  });

  tearDown(() => server.stop());

  Future<http.Response> post(
    Object body, {
    String? auth = 'Bearer $token',
    bool raw = false,
  }) => http.post(
    url,
    headers: {'Content-Type': 'application/json', 'Authorization': ?auth},
    body: raw ? body as String : jsonEncode(body),
  );

  Map<String, dynamic> rpc(String method, {Object? params, int id = 1}) => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': ?params,
  };

  test('rejects requests without or with a wrong bearer token', () async {
    expect((await post(rpc('ping'), auth: null)).statusCode, 401);
    expect((await post(rpc('ping'), auth: 'Bearer wrong')).statusCode, 401);
  });

  test('initialize returns protocol version and server info', () async {
    final res = await post(rpc('initialize'));
    expect(res.statusCode, 200);
    final result = jsonDecode(res.body)['result'];
    expect(result['protocolVersion'], McpServer.protocolVersion);
    expect(result['serverInfo']['name'], 'eatpoint');
  });

  test('notifications/initialized is accepted without a body', () async {
    final res = await post({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    expect(res.statusCode, 202);
    expect(res.body, isEmpty);
  });

  test('tools/list lists both tools with readOnlyHint', () async {
    final res = await post(rpc('tools/list'));
    final tools = jsonDecode(res.body)['result']['tools'] as List;
    expect(tools.map((t) => t['name']), ['echo', 'boom']);
    expect(tools[0]['annotations']['readOnlyHint'], isTrue);
    expect(tools[1]['annotations']['readOnlyHint'], isFalse);
  });

  test('tools/call returns the result as text content', () async {
    final res = await post(
      rpc(
        'tools/call',
        params: {
          'name': 'echo',
          'arguments': {'text': 'hi'},
        },
      ),
    );
    final result = jsonDecode(res.body)['result'];
    expect(result['isError'], isFalse);
    expect(result['content'][0]['type'], 'text');
    expect(jsonDecode(result['content'][0]['text']), {'echo': 'hi'});
  });

  test('a tool error is reported with isError', () async {
    final res = await post(rpc('tools/call', params: {'name': 'boom'}));
    final result = jsonDecode(res.body)['result'];
    expect(result['isError'], isTrue);
    expect(result['content'][0]['text'], 'nope');
  });

  test('an unknown tool is a JSON-RPC error', () async {
    final res = await post(rpc('tools/call', params: {'name': 'missing'}));
    expect(jsonDecode(res.body)['error']['code'], -32602);
  });

  test('an unknown method is -32601', () async {
    final res = await post(rpc('does/not/exist'));
    expect(jsonDecode(res.body)['error']['code'], -32601);
  });

  test('GET is not allowed', () async {
    final res = await http.get(
      url,
      headers: {'Authorization': 'Bearer $token'},
    );
    expect(res.statusCode, 405);
  });

  test('a batch returns one response per request', () async {
    final res = await post([
      rpc('ping', id: 1),
      {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      rpc('tools/list', id: 2),
    ]);
    final list = jsonDecode(res.body) as List;
    expect(list.map((e) => e['id']), [1, 2]);
  });

  test('malformed JSON is a parse error', () async {
    final res = await post('{not json', raw: true);
    expect(jsonDecode(res.body)['error']['code'], -32700);
  });

  test('stop closes the server', () async {
    await server.stop();
    expect(server.isRunning, isFalse);
  });
}
