import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Short, human name of a storage kind.
String storageKindLabel(S s, SyncBackendKind kind) {
  switch (kind) {
    case SyncBackendKind.supabase:
      return s.householdStorageSupabase;
    case SyncBackendKind.webdav:
      return s.householdStorageWebdav;
    case SyncBackendKind.localServer:
      return s.householdStorageLocal;
    case SyncBackendKind.googleDrive:
      return s.householdStorageDrive;
  }
}

/// The text shown for a failed backend call.
String syncFailureReason(S s, Object error) {
  if (error is SyncBackendException) {
    return error.authFailed ? s.householdWrongCredentials : error.message;
  }
  return error.toString();
}
