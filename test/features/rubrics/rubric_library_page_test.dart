import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubrics/rubric_library_page.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fixtures.dart';

Rubric rubric(String id, String title, String subject) {
  final base = essayRubric();
  return Rubric(
    id: id,
    title: title,
    subject: subject,
    createdAt: t0,
    updatedAt: t0,
    levels: base.levels,
    groups: base.groups,
  );
}

/// Three rubrics, edited on different days: lab newest, essay oldest.
Future<void> seedLibrary(AppDatabase db) async {
  final repo = RubricRepository(db);
  await repo.save(rubric('essay', 'Persuasive Essay', 'English'), now: t0);
  await repo.save(
    rubric('story', 'Narrative Writing', 'English'),
    now: t0.add(const Duration(days: 1)),
  );
  await repo.save(
    rubric('lab', 'Lab Report', 'Biology'),
    now: t0.add(const Duration(days: 2)),
  );
}

const _templatesEntry = 'Start from a template';

List<String> cardTitles(WidgetTester tester) => tester
    .widgetList<RubricCard>(find.byType(RubricCard))
    .map((c) => c.cardTitleText)
    .where((t) => t != _templatesEntry)
    .toList();

Future<List<Rubric>> stored(WidgetTester tester, TestApp app) async =>
    (await tester.runAsync(() => RubricRepository(app.db).all()))!;

/// Lets drift's stream queries re-run after a write made through the UI.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

/// Tall enough that the whole (lazily built) list is on screen.
const tall = Size(390, 1800);

Future<void> openMenu(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('More actions for $title'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty library sells the feature and offers templates', (
    tester,
  ) async {
    final app = await pumpPage(tester, const RubricLibraryPage());
    expect(find.text('Build it once. Grade with it all year.'), findsOneWidget);

    await tester.tap(find.text(_templatesEntry));
    await tester.pumpAndSettle();
    expect(app.visited, ['/rubrics/templates']);
  });

  testWidgets('New Rubric opens the builder on a fresh rubric', (tester) async {
    final app = await pumpPage(tester, const RubricLibraryPage());
    await tester.tap(find.text('New Rubric'));
    await tester.pumpAndSettle();
    expect(app.visited.single, startsWith('/build/new'));
  });

  testWidgets('lists rubrics newest edit first with a descriptive hint', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );
    expect(cardTitles(tester), [
      'Lab Report',
      'Narrative Writing',
      'Persuasive Essay',
    ]);
    expect(find.text('Biology · 3 objectives · Simple'), findsOneWidget);
  });

  testWidgets('search narrows by title or subject', (tester) async {
    await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );

    await tester.enterText(find.byType(TextField), 'essay');
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['Persuasive Essay']);

    await tester.enterText(find.byType(TextField), 'biology');
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['Lab Report']);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(cardTitles(tester), isEmpty);
    expect(find.text('No rubrics match'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(cardTitles(tester), hasLength(3));
  });

  testWidgets('subject chips filter the list', (tester) async {
    await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );

    await tester.tap(find.widgetWithText(RubricChip, 'English'));
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['Narrative Writing', 'Persuasive Essay']);

    await tester.tap(find.widgetWithText(RubricChip, 'All'));
    await tester.pumpAndSettle();
    expect(cardTitles(tester), hasLength(3));
  });

  testWidgets('tapping a rubric opens its detail page', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );
    await tester.tap(find.text('Lab Report'));
    await tester.pumpAndSettle();
    expect(app.visited, ['/rubrics/lab']);
  });

  testWidgets('Edit opens the builder on that rubric', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );
    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(app.visited.single, startsWith('/build/lab'));
  });

  testWidgets('Duplicate adds an independent copy', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );
    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Duplicate'));
    await settle(tester);

    final all = await stored(tester, app);
    final copy = all.singleWhere((r) => r.title == 'Lab Report (copy)');
    expect(copy.id, isNot('lab'));
    expect(copy.isTemplate, isFalse);
    expect(copy.groups.map((g) => g.title), ['Writing', 'Research']);
    expect(cardTitles(tester).first, 'Lab Report (copy)');
  });

  testWidgets('Save as template stores a template copy', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );
    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Save as template'));
    await settle(tester);

    final templates = (await stored(tester, app)).where((r) => r.isTemplate);
    expect(templates.single.title, 'Lab Report');
    expect(templates.single.id, isNot('lab'));
    // Templates are not library rubrics.
    expect(cardTitles(tester), hasLength(3));
  });

  testWidgets('Archive moves a rubric into the archived section and back', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );
    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Archive'));
    await settle(tester);

    expect(cardTitles(tester), ['Narrative Writing', 'Persuasive Essay']);
    expect(find.text('ARCHIVED (1)'), findsOneWidget);
    expect(
      (await stored(tester, app)).singleWhere((r) => r.id == 'lab').archived,
      isTrue,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(cardTitles(tester).last, 'Lab Report');

    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Unarchive'));
    await settle(tester);
    expect(find.text('ARCHIVED (1)'), findsNothing);
    expect(cardTitles(tester).first, 'Lab Report');
  });

  testWidgets('Delete confirms, deletes, and can be undone', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricLibraryPage(),
      seed: seedLibrary,
      size: tall,
    );
    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete this rubric?'), findsOneWidget);
    expect(
      find.text('“Lab Report” will be permanently removed from your library.'),
      findsOneWidget,
    );

    // Cancelling keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await stored(tester, app), hasLength(3));

    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(
      (await stored(tester, app)).map((r) => r.id),
      isNot(contains('lab')),
    );
    expect(cardTitles(tester), isNot(contains('Lab Report')));

    await tester.tap(find.text('Undo'));
    await settle(tester);
    final restored = (await stored(
      tester,
      app,
    )).singleWhere((r) => r.id == 'lab');
    expect(restored.updatedAt, t0.add(const Duration(days: 2)));
    expect(cardTitles(tester).first, 'Lab Report');
  });

  testWidgets('deleting a rubric used by assignments says they are safe', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const RubricLibraryPage(),
      size: tall,
      seed: (db) async {
        await seedLibrary(db);
        final course = Course.create(name: 'Biology 9', now: t0);
        await CourseRepository(db).saveCourse(course);
        final lab = (await RubricRepository(db).get('lab'))!;
        for (final title in ['Lab 1', 'Lab 2']) {
          await AssignmentRepository(db).save(
            Assignment.create(
              courseId: course.id,
              title: title,
              rubric: lab,
              now: t0,
            ),
          );
        }
      },
    );
    await openMenu(tester, 'Lab Report');
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(
      find.text(
        '“Lab Report” is used in 2 assignments. Each assignment keeps its own '
        'copy of the rubric, so no grades will change.',
      ),
      findsOneWidget,
    );
  });
}
