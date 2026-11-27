import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/sync_backend.dart';
import 'backend_common.dart';

/// Stores blobs in a Supabase project through three RPC functions, so the
/// table itself is never readable with the anon key.
class SupabaseSyncBackend implements SyncBackend {
  final http.Client _client;
  final Uri projectUrl;
  final String anonKey;
  final String householdId;

  SupabaseSyncBackend(
    this._client, {
    required this.projectUrl,
    required this.anonKey,
    required this.householdId,
  });

  /// Run once in the project's SQL editor (or via [runSetupWithAccessToken]).
  static const setupSql = r'''
create table if not exists public.eatpoint_sync (
  household text not null,
  name text not null,
  data text not null,
  updated_at timestamptz default now(),
  primary key (household, name)
);

alter table public.eatpoint_sync enable row level security;
revoke all on table public.eatpoint_sync from anon, authenticated;

create or replace function public.eatpoint_list(p_household text)
returns setof text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_household is null or p_household !~ '^[0-9a-fA-F]{32,}$' then
    raise exception 'invalid household id';
  end if;
  return query
    select s.name from public.eatpoint_sync s
    where s.household = p_household order by s.name;
end;
$$;

create or replace function public.eatpoint_get(p_household text, p_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  result text;
begin
  if p_household is null or p_household !~ '^[0-9a-fA-F]{32,}$' then
    raise exception 'invalid household id';
  end if;
  select s.data into result from public.eatpoint_sync s
    where s.household = p_household and s.name = p_name;
  return result;
end;
$$;

create or replace function public.eatpoint_put(
  p_household text, p_name text, p_data text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_household is null or p_household !~ '^[0-9a-fA-F]{32,}$' then
    raise exception 'invalid household id';
  end if;
  insert into public.eatpoint_sync (household, name, data, updated_at)
    values (p_household, p_name, p_data, now())
    on conflict (household, name)
    do update set data = excluded.data, updated_at = now();
end;
$$;

revoke all on function public.eatpoint_list(text) from public;
revoke all on function public.eatpoint_get(text, text) from public;
revoke all on function public.eatpoint_put(text, text, text) from public;
grant execute on function public.eatpoint_list(text) to anon;
grant execute on function public.eatpoint_get(text, text) to anon;
grant execute on function public.eatpoint_put(text, text, text) to anon;
''';

  /// Runs [setupSql] through the Supabase management API.
  static Future<void> runSetupWithAccessToken(
    http.Client client, {
    required String projectRef,
    required String personalAccessToken,
  }) async {
    final req = http.Request(
      'POST',
      Uri.parse(
        'https://api.supabase.com/v1/projects/$projectRef/database/query',
      ),
    );
    req.headers['Authorization'] = 'Bearer $personalAccessToken';
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode({'query': setupSql});
    checkStatus(await sendRequest(client, req));
  }

  /// `https://<ref>.supabase.co` gives `<ref>`; null for other hosts.
  static String? projectRefFromUrl(Uri url) {
    final m = RegExp(
      r'^([a-z0-9-]+)\.supabase\.(?:co|in)$',
      caseSensitive: false,
    ).firstMatch(url.host);
    return m?.group(1);
  }

  @override
  SyncBackendKind get kind => SyncBackendKind.supabase;

  Future<http.Response> _rpc(String fn, Map<String, dynamic> body) {
    requireSecureOrLan(projectUrl);
    final segs = projectUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    final req = http.Request(
      'POST',
      projectUrl.replace(pathSegments: [...segs, 'rest', 'v1', 'rpc', fn]),
    );
    req.headers.addAll({
      'apikey': anonKey,
      'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
    });
    req.body = jsonEncode(body);
    return sendRequest(_client, req);
  }

  @override
  Future<void> testConnection() async {
    await list();
  }

  @override
  Future<List<String>> list() async {
    final r = await _rpc('eatpoint_list', {'p_household': householdId});
    checkStatus(r);
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is List) return j.cast<String>();
    } on FormatException {
      // fall through
    } on TypeError {
      // fall through
    }
    throw SyncBackendException('Unexpected answer from Supabase.');
  }

  @override
  Future<Uint8List?> get(String name) async {
    validateBlobName(name);
    final r = await _rpc('eatpoint_get', {
      'p_household': householdId,
      'p_name': name,
    });
    checkStatus(r);
    if (r.bodyBytes.isEmpty) return null;
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j == null) return null;
      if (j is String) return base64Decode(j);
    } on FormatException {
      // fall through
    }
    throw SyncBackendException('Unexpected answer from Supabase.');
  }

  @override
  Future<void> put(String name, Uint8List bytes) async {
    validateBlobName(name);
    final r = await _rpc('eatpoint_put', {
      'p_household': householdId,
      'p_name': name,
      'p_data': base64Encode(bytes),
    });
    checkStatus(r);
  }
}
