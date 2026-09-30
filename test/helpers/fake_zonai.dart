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

  Future<SyncAccount> _as(String email) async {
    if (failNext) {
      failNext = false;
      throw const SyncRemoteException(FailureKind.unauthorized);
    }
    final id = accounts[email];
    if (id == null) throw const SyncRemoteException(FailureKind.unauthorized);
    server.user = id;
    return SyncAccount(id: id, email: email);
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
}

final class MemorySession implements SessionStore {
  SyncAccount? saved;

  @override
  Future<SyncAccount?> read() async => saved;

  @override
  Future<void> write(SyncAccount? account) async => saved = account;
}
