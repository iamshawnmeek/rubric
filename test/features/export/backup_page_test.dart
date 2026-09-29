import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/backup_service.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/export/backup_state.dart';
import 'package:rubric/features/export/export_platform.dart';
import 'package:rubric/features/settings/backup_page.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/db.dart';
import '../../helpers/export_fakes.dart';
import '../../helpers/fixtures.dart';

/// A backup file holding one course ("Imported") and one rubric.
Future<Uint8List> _backupFile({String? settingsName}) async {
  final source = testDatabase();
  addTearDown(source.close);
  await CourseRepository(source)
      .saveCourse(Course(id: 'c9', name: 'Imported', createdAt: t0));
  await RubricRepository(source).save(essayRubric(), now: t0);
  final json = await BackupService(source).export(
    settings: settingsName == null
        ? null
        : AppSettings(teacherName: settingsName).toJson(),
    now: DateTime(2026, 9, 2),
  );
  return Uint8List.fromList(utf8.encode(json));
}

Future<void> _seedLocal(AppDatabase db) async {
  await CourseRepository(db)
      .saveCourse(Course(id: 'c1', name: 'Local class', createdAt: t0));
  await RubricRepository(db).save(
    Rubric(id: 'mine', title: 'Mine', createdAt: t0, updatedAt: t0),
    now: t0,
  );
}

void main() {
  late FakeExportPlatform platform;
  setUp(() => platform = FakeExportPlatform());

  Future<TestApp> pump(WidgetTester tester) => pumpPage(
    tester,
    const BackupPage(),
    seed: _seedLocal,
    overrides: [exportPlatformProvider.overrideWithValue(platform)],
  );

  Future<List<String>> courseNames(TestApp app) async =>
      (await app.db.select(app.db.courses).get()).map((c) => c.name).toList();

  testWidgets('shows last backup and what is on the device', (tester) async {
    await pump(tester);
    expect(find.text('Never backed up'), findsOneWidget);
    expect(find.textContaining('1 class'), findsWidgets);
    expect(find.textContaining('1 rubric'), findsOneWidget);
    expect(find.text('3 items'), findsNothing);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('Back Up Now shares a dated backup and records it', (
    tester,
  ) async {
    final app = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('backupNow')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final file = platform.shared.single;
    expect(file.mimeType, 'application/json');
    expect(
      file.filename,
      matches(RegExp(r'^rubric-backup-\d{4}-\d{2}-\d{2}\.json$')),
    );
    final doc = BackupService.parse(utf8.decode(file.bytes));
    expect(doc.courses.single.name, 'Local class');
    expect(doc.settings, isNotNull);

    expect(app.read(lastBackupProvider), isNotNull);
    expect(find.text('Never backed up'), findsNothing);
    expect(find.text('Backup saved.'), findsOneWidget);
  });

  testWidgets('a dismissed share sheet is not recorded as a backup', (
    tester,
  ) async {
    platform.shareCompletes = false;
    final app = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('backupNow')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(platform.shared, hasLength(1));
    expect(app.read(lastBackupProvider), isNull);
    expect(find.text('Never backed up'), findsOneWidget);
  });

  Future<void> openRestore(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('restore summarises the file, then merges', (tester) async {
    final app = await pump(tester);
    platform.pickResult = (name: 'b.json', bytes: await _backupFile());
    await openRestore(tester);

    expect(find.text('Restore backup'), findsOneWidget);
    expect(find.text('1 rubric · 1 class'), findsOneWidget);
    expect(find.text('Merge Backup'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('restoreConfirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restoreConfirm')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(
      await tester.runAsync(() => courseNames(app)),
      unorderedEquals(['Local class', 'Imported']),
    );
    expect(find.text('Restored 2 items.'), findsOneWidget);
  });

  testWidgets('replace asks first, wipes, restores settings, and can undo', (
    tester,
  ) async {
    final app = await pump(tester);
    platform.pickResult = (
      name: 'b.json',
      bytes: await _backupFile(settingsName: 'Ms. Backup'),
    );
    await openRestore(tester);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Deletes everything'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('restoreConfirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restoreConfirm')));
    await tester.pumpAndSettle();

    // The destructive confirmation.
    expect(find.text('Replace everything?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => courseNames(app)), ['Imported']);
    final settings = app.read(settingsProvider);
    expect(settings.teacherName, 'Ms. Backup');
    expect(settings.onboardingComplete, isTrue);

    await tester.tap(find.text('Undo'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => courseNames(app)), ['Local class']);
    expect(app.read(settingsProvider).teacherName, '');
  });

  testWidgets('cancelling the replace confirmation changes nothing', (
    tester,
  ) async {
    final app = await pump(tester);
    platform.pickResult = (name: 'b.json', bytes: await _backupFile());
    await openRestore(tester);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('restoreConfirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restoreConfirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => courseNames(app)), ['Local class']);
  });

  testWidgets('a file that is not a backup is explained, not imported', (
    tester,
  ) async {
    final app = await pump(tester);
    platform.pickResult = (
      name: 'notes.json',
      bytes: Uint8List.fromList(utf8.encode('{"hello": "world"}')),
    );
    await openRestore(tester);
    expect(find.text('Can’t restore this file'), findsOneWidget);
    expect(find.textContaining('isn’t a Rubric backup'), findsOneWidget);
    expect(await tester.runAsync(() => courseNames(app)), ['Local class']);
  });
}
