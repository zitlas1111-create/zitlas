import 'local_storage_service.dart';

/// Mirrors `ZitlasAccountGuard` in `frontend/assets/js/firebase-config.js`.
///
/// Local cache is per-device, not per-user. If a second ZITLAS account signs
/// in on the same device, every user-scoped cached key must be purged before
/// any feature reads (or re-uploads) it — otherwise account B silently
/// inherits account A's cached plans/goal/membership/wallet data. This was a
/// real cross-account data-leak bug on web; the fix ports 1:1.
class AccountGuard {
  AccountGuard._();
  static final AccountGuard instance = AccountGuard._();

  static const _ownerKey = 'zitlas_cache_owner_uid';

  /// Device/UI-scoped keys that legitimately survive an account switch —
  /// same list as `KEEP_KEYS` on web.
  static const _deviceKeys = {
    'zitlas_theme',
    'zitlas_language',
    'zitlas_trial_mode',
    'zitlas_step_perm_state',
    'zitlas_remember',
  };

  LocalStorageService get _storage => LocalStorageService.instance;

  /// Claims the local cache for [uid]. Purges every non-device-scoped key
  /// first if the cache belonged to a different account. No-ops (adopts
  /// without purging) on a fresh device with no recorded owner yet. Call
  /// this the moment sign-in/sign-up/session-restore resolves a uid.
  Future<void> beginSession(String uid) async {
    final owner = _storage.getString(_ownerKey);
    if (owner == uid) return;
    if (owner != null && owner != uid) {
      await _storage.clearExcept(_deviceKeys);
    }
    await _storage.setString(_ownerKey, uid);
  }

  /// Full purge on logout — including the owner stamp, releasing the cache
  /// so the next `beginSession` (any uid) adopts without a warning purge.
  Future<void> clearUserCache() async {
    await _storage.clearExcept(_deviceKeys);
  }
}
