// Post-deploy smoke test for a Rubric server.
//
//   tool/dart run tool/deploy/smoke.dart https://rubric.example.org
//
// Signs up two throwaway accounts and proves what the app depends on:
// creates and owner-scoped pulls through zonai_sync's own adapter, and that
// one teacher can neither list nor read another's rows. It exits non-zero
// on any failure, so tool/deploy/deploy.sh can gate on it.
//
// It leaves the two accounts and one course row behind. They are tagged
// `smoke-<time>@rubric.invalid` (a reserved TLD), so they can never collide
// with a real teacher.
import 'dart:io';

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

  Future<(ZonaiClient, String)> teacher(String name) async {
    final client = ZonaiClient(baseUrl: base);
    final session = await client.auth.signUp(
      body: SignUpAuthBody(
        table: 'users',
        email: 'smoke-$name-$stamp@rubric.invalid',
        password: 'smoke-${stamp}_correct-horse',
      ),
    );
    return (client, session!.user['id']! as String);
  }

  try {
    final (aClient, a) = await teacher('a');
    final (bClient, _) = await teacher('b');
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
  } on Object catch (e) {
    check('smoke run', ok: false, detail: e);
  }

  stdout.writeln(failures == 0 ? 'SMOKE PASSED' : 'SMOKE FAILED ($failures)');
  exit(failures == 0 ? 0 : 1);
}
