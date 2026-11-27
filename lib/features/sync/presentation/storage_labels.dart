import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';
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
  if (error is GoogleSignInFailure) {
    final detail = [
      error.code,
      if ((error.description ?? '').trim().isNotEmpty)
        error.description!.trim(),
    ].join(': ');
    if (error.misconfigured) return s.householdDriveErrorSetup(detail);
    if (error.canceled) return s.householdDriveErrorCanceled;
    return s.householdDriveErrorOther(detail);
  }
  if (error is SyncBackendException) {
    return error.authFailed ? s.householdWrongCredentials : error.message;
  }
  return error.toString();
}
