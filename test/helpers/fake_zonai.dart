import 'package:rubric/sync/sync_service.dart';
import 'package:zonai_sync/testing.dart';
import 'package:zonai_sync/zonai_sync.dart';

export 'package:zonai_sync/testing.dart' show FakeZonai;

/// A signed-in session for [FakeZonai]: one teacher account, any device.
final class FakeAuth implements AuthGateway {
  new(this.server, {this.accounts = const {'teacher@school.test': 'u1'}});

  final FakeZonai server;
  final Map<String, String> accounts;
  bool failNext = false;

  /// Thrown by the next sign-in or sign-up instead of [failNext]'s refusal.
  Exception? failNextWith;

  Future<SyncAccount> _as(String email) async {
    if (failNextWith case final error?) {
      failNextWith = null;
      throw error;
    }
    if (failNext) {
      failNext = false;
      throw const SyncRemoteException(FailureKind.unauthorized);
    }
    final id = accounts[email];
    if (id == null || deleted.contains(id)) {
      throw const SyncRemoteException(FailureKind.unauthorized);
    }
    server.user = id;
    return SyncAccount(
      id: id,
      email: email,
      verified: verifiedIds.contains(id),
    );
  }

  @override
  Future<SyncAccount> signIn({
    required String email,
    required String password,
  }) => _as(email);

  @override
  Future<SyncAccount> signUp({
    required String email,
    required String password,
  }) => _as(email);

  @override
  Future<void> signOut() async {}

  /// Addresses [sendPasswordReset] and [sendVerification] mailed, in order.
  final resetsSent = <String>[];
  final verificationsSent = <String>[];

  /// Accounts whose address the server reports as confirmed.
  final verifiedIds = <String>{};

  /// Thrown by the next reset or verification email instead of sending it.
  Exception? failNextSend;

  void _maybeFailSend() {
    if (failNextSend case final error?) {
      failNextSend = null;
      throw error;
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _maybeFailSend();
    resetsSent.add(email);
  }

  @override
  Future<void> sendVerification(String email) async {
    _maybeFailSend();
    verificationsSent.add(email);
  }

  @override
  Future<bool> isVerified(String id) async => verifiedIds.contains(id);

  /// Account ids [deleteAccount] removed, in order.
  final deleted = <String>[];
  Exception? failDelete;

  @override
  Future<void> deleteAccount(String id) async {
    if (failDelete case final error?) {
      failDelete = null;
      throw error;
    }
    for (final rows in server.tables.values) {
      rows.removeWhere((_, row) => row['owner_id'] == id);
    }
    deleted.add(id);
  }
}

final class MemorySession implements SessionStore {
  SyncAccount? saved;

  @override
  Future<SyncAccount?> read() async => saved;

  @override
  Future<void> write(SyncAccount? account) async => saved = account;
}
