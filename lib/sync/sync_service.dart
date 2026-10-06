import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/sync_writer.dart';
import 'package:rubric/sync/account_tables.dart';
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

  /// Permanently deletes account [id] and every row it owns on the server.
  Future<void> deleteAccount(String id);
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
    // The account goes first. While it is still set, a pass starting during
    // the engine's clear would see the signed-out store, re-adopt it for this
    // account and pull its data straight back onto the device. Unset, every
    // pass (and every check inside a running one) sees "signed out".
    _account = null;
    _publish();
    try {
      await _auth.signOut();
    } on Object {
      // Offline or already expired: the local sign-out must still happen.
    }
    await _engine.signOut();
    await _session.write(null);
    _publish();
  }

  /// Permanently deletes the account: every row it owns on the server, then
  /// the account itself, then its data on this device (as [signOut]).
  ///
  /// Sync stops first, the same way [signOut] stops it, so no pass can push a
  /// queued row back after its table was emptied. If the server deletion
  /// fails (offline, say) nothing is lost: the account is restored and sync
  /// resumes, and the error reaches the caller to report.
  Future<void> deleteAccount() async {
    final account = _account;
    if (account == null) throw StateError('Not signed in');
    _account = null;
    _publish();
    try {
      await _auth.deleteAccount(account.id);
    } on Object {
      _account = account;
      _publish();
      _engine.start();
      rethrow;
    }
    try {
      await _auth.signOut();
    } on Object {
      // The session went with the account; only the local part remains.
    }
    await _engine.signOut();
    await _session.write(null);
    _publish();
  }

  /// After the session expired ([SyncPhase.needsAuth]) and the teacher
  /// signed in again with the same account.
  Future<void> resume() => _engine.resume();

  Future<void> retryDeadLetter(int id) => _engine.retryDeadLetter(id);

  Future<void> discardDeadLetter(int id) => _engine.discardDeadLetter(id);

  /// Runs [op], a bulk change that writes the database directly (sample data,
  /// a restored backup), and then queues what it changed for the server.
  ///
  /// Signed out, it just runs [op]. Signed in, every synced row is snapshotted
  /// first and diffed afterwards:
  /// - a row [op] added or edited is queued with only the fields that differ;
  /// - a row [op] removed is put back and deleted through the engine, so the
  ///   server gets a tombstone. Deleting it only locally would leave it alive
  ///   on the server and on every other device — the drift store forgets a
  ///   row once its data is gone, so the engine cannot tombstone it after
  ///   the fact.
  ///
  /// A pull landing while [op] runs is diffed like [op]'s own changes and
  /// pushed back unchanged — harmless, since it carries the pulled revision.
  Future<T> bulk<T>(Future<T> Function() op) async {
    if (_account == null) return await op();
    final tables = rubricSyncTables(_db, () => _account?.id);
    final before = <String, Map<String, Map<String, Object?>>>{
      for (final table in tables)
        table.name: {
          for (final id in await table.ids()) id: ?await table.read(id),
        },
    };
    final result = await op();
    if (_account == null) return result;

    // Parents first, so a child's foreign key holds when it is put back.
    final gone = <DriftSyncTable, List<String>>{};
    for (final table in tables) {
      final now = (await table.ids()).toSet();
      final removed = [
        for (final id in before[table.name]!.keys)
          if (!now.contains(id)) id,
      ];
      for (final id in removed) {
        await table.write(before[table.name]![id]!);
      }
      gone[table] = removed;
      for (final id in now) {
        final wire = await table.read(id);
        if (wire == null) continue;
        final old = before[table.name]![id];
        final changed = {
          for (final e in wire.entries)
            if (old == null || old[e.key] != e.value) e.key,
        };
        if (changed.isEmpty) continue;
        await _engine.write(table.name, wire, changed: changed);
      }
    }
    // Children first, the order a cascade deletes in.
    for (final table in tables.reversed) {
      for (final id in gone[table]!) {
        await _engine.delete(table.name, id);
      }
    }
    return result;
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

/// [SyncService.bulk] when sync is set up, else just [op] (tests, or before
/// startup finishes).
Future<T> bulkChange<T>(SyncService? sync, Future<T> Function() op) =>
    sync == null ? op() : sync.bulk(op);

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
      body: SignUpAuthBody(table: accountTable, email: email, password: password),
    ),
    email,
  );

  @override
  Future<SyncAccount> signIn({
    required String email,
    required String password,
  }) async => _account(
    await _client.auth.signIn(
      body: SignInAuthBody(table: accountTable, email: email, password: password),
    ),
    email,
  );

  @override
  Future<void> signOut() => _client.auth.logout();

  /// Children first ([accountDeletionOrder]), each table in one request,
  /// then the user row. The server's rules allow a teacher to delete only
  /// their own rows (server/lib/src/rules/), so `owner_id` here is a filter,
  /// not the guard. Re-running after a partial failure is safe: emptied
  /// tables just match nothing.
  @override
  Future<void> deleteAccount(String id) async {
    for (final table in accountDeletionOrder) {
      await _client.db.deleteMany(
        body: DeleteBody(table: table, where: Eq('owner_id', id)),
      );
    }
    await _client.db.delete(
      body: DeleteOneBody(table: accountTable, where: Eq('id', id)),
    );
  }
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
