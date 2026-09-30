import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rubric/app/app.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zonai_sync/zonai_sync.dart';

/// One leg of the two-device sync check, against a real zonai server
/// (server/README.md). Run by `tool/sync_e2e.sh`, which plays the legs on two
/// devices in turn:
///
/// 1. `writer` (device A, fresh install): creates an account from Settings,
///    loads the sample classroom, adds a class named after [nonce].
/// 2. `reader` (device B, fresh install): signs in from Settings, waits for
///    everything A made, then renames that class and removes a student.
/// 3. `checker` (device A again, session kept): waits for B's edits.
///
/// Each leg prints one `SYNC_E2E {...}` line with what the device holds, so
/// the script can compare the devices rather than trust either one.
const role = String.fromEnvironment('ROLE');
const email = String.fromEnvironment('EMAIL');
const nonce = String.fromEnvironment('NONCE');
const password = 'correct horse battery';

String get className => 'Period $nonce';
String get renamed => '$className (edited on the other device)';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(String name) => binding.takeScreenshot('${role}_$name');

  Future<void> tap(WidgetTester tester, Finder finder) async {
    expect(finder, findsAny, reason: 'nothing to tap: $finder');
    await tester.ensureVisible(finder.first);
    await settle(tester, 300);
    await tester.tap(finder.first);
    await settle(tester);
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(RubricApp)));

  /// Pumps until [done] holds, failing with [what] after [timeout].
  Future<void> waitFor(
    WidgetTester tester,
    String what,
    FutureOr<bool> Function() done, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!await done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out waiting: $what');
      await settle(tester, 500);
    }
  }

  Future<Map<String, Object?>> holdings(WidgetTester tester) async {
    final db = container(tester).read(databaseProvider);
    Future<int> count(String table) async =>
        (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
            .read<int>('n');
    final courses = await db.select(db.courses).get();
    return {
      'role': role,
      'courses': courses.length,
      'students': await count('students'),
      'assignments': await count('assignments'),
      'evaluations': await count('evaluations'),
      'rubrics': await count('rubrics'),
      'snippets': await count('comment_snippets'),
      'class_names': [for (final c in courses) c.name]..sort(),
    };
  }

  Future<void> report(WidgetTester tester) async {
    final sync = container(tester).read(syncServiceProvider)!;
    // ignore: avoid_print — the script reads this line.
    print(
      'SYNC_E2E ${jsonEncode({...await holdings(tester), 'pending': sync.state.status.pending, 'dead': sync.state.status.deadLetters.length, 'phase': sync.state.status.phase.name})}',
    );
  }

  Future<void> start(WidgetTester tester) async {
    await binding.convertFlutterSurfaceToImage();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'settings.v1',
      jsonEncode(const AppSettings(onboardingComplete: true).toJson()),
    );
    unawaited(app.main());
    await settle(tester, 3500);
  }

  Future<void> signInFromSettings(
    WidgetTester tester, {
    required bool create,
  }) async {
    await tap(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tap(tester, find.byKey(const Key('sync.signIn')));
    if (create) await tap(tester, find.text('Create account').first);
    await tester.enterText(find.byKey(const Key('sync.email')), email);
    await tester.enterText(find.byKey(const Key('sync.password')), password);
    await settle(tester, 300);
    await shot('sign_in_sheet');
    await tap(tester, find.byKey(const Key('sync.submit')));
    final sync = container(tester).read(syncServiceProvider)!;
    await waitFor(tester, 'signed in', () => sync.state.signedIn);
  }

  Future<void> synced(WidgetTester tester) async {
    final sync = container(tester).read(syncServiceProvider)!;
    await waitFor(tester, 'nothing pending', () async {
      await sync.syncNow();
      final s = sync.state.status;
      return s.pending == 0 && s.phase == SyncPhase.idle;
    });
    expect(sync.state.status.deadLetters, isEmpty);
  }

  testWidgets('sync e2e: $role', (tester) async {
    expect(role, isIn(['writer', 'reader', 'checker']));
    expect(email, isNotEmpty);
    expect(nonce, isNotEmpty);
    await start(tester);

    switch (role) {
      case 'writer':
        await signInFromSettings(tester, create: true);
        await tap(tester, find.text('Load sample data'));
        await settle(tester, 2000);
        await container(tester)
            .read(courseRepositoryProvider)
            .saveCourse(Course.create(name: className));
        await synced(tester);
        await shot('settings_synced');

      case 'reader':
        await signInFromSettings(tester, create: false);
        final courses = container(tester).read(courseRepositoryProvider);
        await waitFor(tester, "the writer's class", () async {
          final names = [for (final c in await courses.allCourses()) c.name];
          return names.contains(className);
        });
        await synced(tester);
        await report(tester); // what arrived, before editing
        final course = (await courses.allCourses()).firstWhere(
          (c) => c.name == className,
        );
        await courses.saveCourse(course.copyWith(name: renamed));
        final student = (await courses.allStudents()).first;
        await courses.deleteStudent(student.id);
        await synced(tester);
        await shot('settings_synced');

      case 'checker':
        final sync = container(tester).read(syncServiceProvider)!;
        expect(sync.state.account?.email, email, reason: 'session kept');
        final courses = container(tester).read(courseRepositoryProvider);
        await waitFor(tester, "the reader's rename", () async {
          await sync.syncNow();
          final names = [for (final c in await courses.allCourses()) c.name];
          return names.contains(renamed);
        });
        await synced(tester);
        await tap(
          tester,
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Classes'),
          ),
        );
        await shot('classes');
    }
    await report(tester);
  });
}
