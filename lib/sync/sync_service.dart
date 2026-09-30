import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/sync_writer.dart';
import 'package:rubric/sync/sync_tables.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_sync/zonai_sync.dart';
import 'package:zonai_sync_drift/zonai_sync_drift.dart';

/// The signed-in teacher.
@immutable
final class SyncAccount {
  const new({required this.id, required this.email});

  factory fromJson(Map<String, Object?> json) =>
      SyncAccount(id: json['id']! as String, email: json['email']! as String);

  final String id;
  final String email;

  Map<String, Object?> toJson() => {'id': id, 'email': email};
}

/// Signs teachers in and out of the server. The real one talks to zonai; tests
/// supply a fake.
abstract interface class AuthGateway {
  Future<SyncAccount> signUp({required String email, required String password});
  Future<SyncAccount> signIn({required String email, required String password});
  Future<void> signOut();
}

/// Where the session survives app restarts (the platform keychain in the app).
abstract interface class SessionStore {
  Future<SyncAccount?> read();
  Future<void> write(SyncAccount? account);
}

/// What the UI shows about sync.
@immutable
final class SyncState {
  const new({required this.account, required this.status});

  static const signedOut = SyncState(account: null, status: SyncStatus.initial);

  final SyncAccount? account;
  final SyncStatus status;

  bool get signedIn => account != null;
}

/// Owns sync for the app: the session, the local bookkeeping store and the
/// engine. Every repository write goes through it ([SyncWriter]): signed out,
/// straight to the local database; signed in, through the engine so the change
/// is also queued for the server.
final class SyncService implements SyncWriter {
  new _({
    required AppDatabase db,
    required DriftSyncStore store,
    required SyncRemote remote,
    required this._auth,
    required this._session,
    required this._account,
    required Duration pullOverlap,
  }) : _db = db,
       _local = LocalWriter(db) {
    _engine = SyncEngine(
      remote: remote,
      local: store,
      tables: syncTables,
      account: () => _account?.id,
      pullOverlap: pullOverlap,
    );
    _statusSub = _engine.status.listen((_) => _publish());
  }

  /// Opens sync for [db], restoring a saved session if there is one.
  static Future<SyncService> open({
    required AppDatabase db,
    required SyncRemote remote,
    required AuthGateway auth,
    required SessionStore session,
    Duration pullOverlap = const Duration(seconds: 2),
  }) async {
    // The adapters ask "who owns this row" of the service, which exists only
    // after the store it needs; the holder breaks that cycle.
    SyncService? holder;
    final store = await DriftSyncStore.open(
      db,
      rubricSyncTables(db, () => holder?._account?.id),
    );
    return holder = SyncService._(
      db: db,
      store: store,
      remote: remote,
      auth: auth,
      session: session,
      account: await session.read(),
      pullOverlap: pullOverlap,
    );
  }

  final AppDatabase _db;
  final AuthGateway _auth;
  final SessionStore _session;
  final LocalWriter _local;
  late final SyncEngine _engine;
  late final StreamSubscription<SyncStatus> _statusSub;
  SyncAccount? _account;

  final _state = StreamController<SyncState>.broadcast();

  SyncState get state =>
      SyncState(account: _account, status: _engine.currentStatus);

  Stream<SyncState> get states => _state.stream;

  void _publish() {
    if (!_state.isClosed) _state.add(state);
  }

  /// Starts background sync if someone is signed in.
  void start() {
    if (_account != null) _engine.start();
  }

  /// Call when the app returns to the foreground or connectivity returns.
  Future<void> nudge() =>
      _account == null ? Future.value() : _engine.requestSync();

  /// "Sync now".
  Future<void> syncNow() => _account == null ? Future.value() : _engine.sync();

  Future<void> signUp({required String email, required String password}) =>
      _begin(_auth.signUp(email: email.trim(), password: password));

  Future<void> signIn({required String email, required String password}) =>
      _begin(_auth.signIn(email: email.trim(), password: password));

  Future<void> _begin(Future<SyncAccount> signingIn) async {
    final account = await signingIn;
    _account = account;
    await _session.write(account);
    _publish();
    // The first sync adopts this device's data: a device nobody has signed
    // in on keeps what the teacher made and uploads it.
    _engine.start();
  }

  /// Signs out and removes this account's data from the device. It stays on
  /// the server and comes back at the next sign-in.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Object {
      // Offline or already expired: the local sign-out must still happen.
    }
    await _engine.signOut();
    _account = null;
    await _session.write(null);
    _publish();
  }

  /// After the session expired ([SyncPhase.needsAuth]) and the teacher
  /// signed in again with the same account.
  Future<void> resume() => _engine.resume();

  Future<void> retryDeadLetter(int id) => _engine.retryDeadLetter(id);

  Future<void> discardDeadLetter(int id) => _engine.discardDeadLetter(id);

  /// Queues every local row for upload — after a bulk import (sample data, a
  /// restored backup) that wrote the database directly.
  Future<void> requeueAll() async {
    if (_account == null) return;
    for (final table in rubricSyncTables(_db, () => _account?.id)) {
      for (final id in await table.ids()) {
        final wire = await table.read(id);
        if (wire == null) continue;
        await _engine.write(table.name, wire, changed: wire.keys.toSet());
      }
    }
  }

  // ---- SyncWriter ----

  @override
  Future<void> upsert(String table, Map<String, Object?> wire) {
    final account = _account;
    if (account == null) return _local.upsert(table, wire);
    return _engine.write(table, {...wire, 'owner_id': account.id});
  }

  @override
  Future<void> delete(String table, String id) =>
      _account == null ? _local.delete(table, id) : _engine.delete(table, id);

  Future<void> dispose() async {
    await _statusSub.cancel();
    await _engine.dispose();
    await _state.close();
  }
}

/// [AuthGateway] over zonai's password auth (`users` table).
final class ZonaiAuthGateway implements AuthGateway {
  new(this._client);

  final ZonaiClient _client;

  SyncAccount _account(AuthSession? session, String email) {
    final id = session?.user['id'];
    if (id is! String) throw StateError('The server did not return a user');
    return SyncAccount(id: id, email: email);
  }

  @override
  Future<SyncAccount> signUp({
    required String email,
    required String password,
  }) async => _account(
    await _client.auth.signUp(
      body: SignUpAuthBody(table: 'users', email: email, password: password),
    ),
    email,
  );

  @override
  Future<SyncAccount> signIn({
    required String email,
    required String password,
  }) async => _account(
    await _client.auth.signIn(
      body: SignInAuthBody(table: 'users', email: email, password: password),
    ),
    email,
  );

  @override
  Future<void> signOut() => _client.auth.logout();
}

/// Keeps the account in any string key-value store (the keychain in the app).
final class KeyValueSessionStore implements SessionStore {
  new({required this.read_, required this.write_});

  final Future<String?> Function(String key) read_;
  final Future<void> Function(String key, String? value) write_;

  static const _key = 'rubric.sync.account';

  @override
  Future<SyncAccount?> read() async {
    final raw = await read_(_key);
    if (raw == null) return null;
    try {
      return SyncAccount.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(SyncAccount? account) =>
      write_(_key, account == null ? null : jsonEncode(account.toJson()));
}
