// Post-deploy smoke test for a Rubric server.
//
//   tool/dart run tool/deploy/smoke.dart https://rubric.example.org
//
// Signs up two throwaway accounts and proves what the app depends on:
// creates and owner-scoped pulls through zonai_sync's own adapter, and that
// one teacher can neither list nor read another's rows. It exits non-zero
// on any failure, so tool/deploy/deploy.sh can gate on it.
//
// It also proves account deletion: the other teacher cannot delete these
// rows, and the owner deletes everything they own and then their account,
// after which they can no longer sign in. So it cleans up after itself. Its
// accounts are tagged `smoke-<time>@rubric.invalid` (a reserved TLD), so they
// can never collide with a real teacher.
import 'dart:io';

import 'package:rubric/sync/account_tables.dart';
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_sync/zonai_sync.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: smoke.dart <server base url>');
    exit(64);
  }
  final base = Uri.parse(args.single);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  var failures = 0;

  void check(String what, {required bool ok, Object? detail}) {
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $what${ok ? '' : ': $detail'}');
    if (!ok) failures++;
  }

  String emailOf(String name) => 'smoke-$name-$stamp@rubric.invalid';
  final password = 'smoke-${stamp}_correct-horse';

  Future<(ZonaiClient, String)> teacher(String name) async {
    final client = ZonaiClient(baseUrl: base);
    final session = await client.auth.signUp(
      body: SignUpAuthBody(
        table: accountTable,
        email: emailOf(name),
        password: password,
      ),
    );
    return (client, session!.user['id']! as String);
  }

  /// Deletes everything [owner] owns, children first, then their account:
  /// the same steps the app's "Delete account" takes.
  Future<void> deleteAccount(ZonaiClient client, String owner) async {
    for (final table in accountDeletionOrder) {
      await client.db.deleteMany(
        body: DeleteBody(table: table, where: Eq('owner_id', owner)),
      );
    }
    await client.db.delete(
      body: DeleteOneBody(table: accountTable, where: Eq('id', owner)),
    );
  }

  try {
    final (aClient, a) = await teacher('a');
    final (bClient, b) = await teacher('b');
    check('two accounts signed up', ok: true);

    final aRemote = ZonaiSyncRemote(aClient);
    final id = 'smoke_course_$stamp';
    final row = await aRemote.create('courses', {
      'id': id,
      'owner_id': a,
      'name': 'Smoke test',
      'section': '',
      'term': '',
      'archived': 0,
      'created_on': stamp,
    });
    check(
      'create returns a server-stamped row',
      ok: row.rev == 0 && row.updatedAt > 0,
      detail: row.data,
    );

    final mine = await aRemote.pull(
      'courses',
      scope: SyncScope('owner_id', a),
      after: null,
      limit: 50,
    );
    check(
      'the owner pulls their row',
      ok: mine.rows.any((r) => r.id == id),
      detail: mine.rows.length,
    );

    final bRemote = ZonaiSyncRemote(bClient);
    final theirs = await bRemote.pull(
      'courses',
      scope: null,
      after: null,
      limit: 50,
    );
    check(
      "another teacher's list never contains it",
      ok: theirs.rows.every((r) => r.id != id),
      detail: theirs.rows.map((r) => r.id).toList(),
    );
    check(
      "another teacher can't read it",
      ok: await bRemote.read('courses', id) == null,
    );

    // Account deletion. Another teacher's delete must not touch a's rows.
    var refused = false;
    try {
      await bClient.db.deleteMany(
        body: DeleteBody(table: 'courses', where: Eq('owner_id', a)),
      );
    } on Object {
      refused = true;
    }
    final stillThere = await aRemote.read('courses', id) != null;
    check(
      "another teacher can't delete it",
      ok: stillThere,
      detail: refused ? 'refused, yet the row is gone' : 'the row was deleted',
    );

    // The positive control: the same sign-in works before the deletion, so
    // its failure afterwards means the account is gone, not a typo.
    final before = await ZonaiClient(baseUrl: base).auth.signIn(
      body: SignInAuthBody(
        table: accountTable,
        email: emailOf('a'),
        password: password,
      ),
    );
    check('the owner can sign in', ok: before?.user['id'] == a);

    await deleteAccount(aClient, a);
    check(
      'the owner deleted their rows',
      ok: await aRemote.read('courses', id) == null,
    );
    var signInFailed = false;
    try {
      await ZonaiClient(baseUrl: base).auth.signIn(
        body: SignInAuthBody(
          table: accountTable,
          email: emailOf('a'),
          password: password,
        ),
      );
    } on Object {
      signInFailed = true;
    }
    check('a deleted account can no longer sign in', ok: signInFailed);

    await deleteAccount(bClient, b);
    check('the second account cleaned up', ok: true);
  } on Object catch (e) {
    check('smoke run', ok: false, detail: e);
  }

  stdout.writeln(failures == 0 ? 'SMOKE PASSED' : 'SMOKE FAILED ($failures)');
  exit(failures == 0 ? 0 : 1);
}
