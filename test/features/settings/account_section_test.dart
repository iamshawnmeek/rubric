import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/features/settings/settings_page.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/sync/sync_service.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/db.dart';
import '../../helpers/fake_zonai.dart';

final AppLocalizations l = lookupAppLocalizations(const Locale('en'));

/// The service was opened outside fake async, so its database work and
/// status events run on the real event loop: let them land, then pump.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  late FakeZonai server;
  late SyncService sync;

  Future<void> pumpSettings(WidgetTester tester) async {
    server = FakeZonai();
    await tester.runAsync(() async {
      final db = testDatabase();
      addTearDown(db.close);
      sync = await SyncService.open(
        db: db,
        remote: server,
        auth: FakeAuth(server),
        session: MemorySession(),
      );
    });
    await pumpPage(
      tester,
      const SettingsPage(),
      overrides: [syncServiceProvider.overrideWithValue(sync)],
    );
  }

  Future<void> signIn(
    WidgetTester tester, {
    String password = 'password1',
  }) async {
    await tapKey(tester, 'sync.signIn');
    await tester.enterText(
      find.byKey(const Key('sync.email')),
      'teacher@school.test',
    );
    await tester.enterText(find.byKey(const Key('sync.password')), password);
    await tapKey(tester, 'sync.submit');
  }

  // The engine owns timers; stop them before the test's pending-timer check.
  Future<void> dispose(WidgetTester tester) =>
      tester.runAsync(sync.dispose).then((_) => tester.pumpAndSettle());

  testWidgets('signed out, Settings offers sign-in first', (tester) async {
    await pumpSettings(tester);

    expect(find.text(l.syncSectionTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l.syncSignedOutHint), findsOneWidget);
    expect(find.byKey(const Key('sync.signOut')), findsNothing);
    await dispose(tester);
  });

  testWidgets('signing in from the sheet shows the account and its status', (
    tester,
  ) async {
    await pumpSettings(tester);
    await signIn(tester);

    expect(sync.state.account?.email, 'teacher@school.test');
    expect(find.text('teacher@school.test'), findsOneWidget);
    expect(find.byKey(const Key('sync.signOut')), findsOneWidget);
    expect(find.byKey(const Key('sync.submit')), findsNothing);
    await dispose(tester);
  });

  testWidgets('a short password is refused before anything is sent', (
    tester,
  ) async {
    await pumpSettings(tester);
    await signIn(tester, password: 'short');

    expect(find.text(l.syncFormInvalid), findsOneWidget);
    expect(sync.state.signedIn, isFalse);
    expect(server.calls, isEmpty);
    await dispose(tester);
  });

  testWidgets('sign-out asks first, then signs out', (tester) async {
    await pumpSettings(tester);
    await signIn(tester);

    await tapKey(tester, 'sync.signOut');
    expect(find.text(l.syncSignOutConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l.syncSignOutTitle).last);
    await settle(tester);

    expect(sync.state.signedIn, isFalse);
    expect(find.byKey(const Key('sync.signIn')), findsOneWidget);
    await dispose(tester);
  });
}
