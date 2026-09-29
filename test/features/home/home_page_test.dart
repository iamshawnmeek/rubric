import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/sample_data.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/home/home_page.dart';
import 'package:rubric/features/home/home_providers.dart';

import '../../helpers/app_harness.dart';

/// Wednesday morning.
final _now = DateTime(2026, 9, 30, 10);

void main() {
  final clock = homeClockProvider.overrideWithValue(() => _now);

  testWidgets('greets the teacher by name', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: [clock],
      settings: const AppSettings(
        onboardingComplete: true,
        teacherName: 'Ms. Rivera',
      ),
    );
    expect(find.text('Good morning, Ms. Rivera'), findsOneWidget);
  });

  testWidgets('greets plainly when no name is set', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: [
        homeClockProvider.overrideWithValue(() => DateTime(2026, 9, 30, 19)),
      ],
    );
    expect(find.text('Good evening'), findsOneWidget);
  });

  testWidgets('renders the grading queue from seeded data', (tester) async {
    final app = await pumpPage(
      tester,
      const HomePage(),
      overrides: [clock],
      seed: (db) => loadSampleData(db, now: _now),
    );

    // Stats: 2 classes, 48 students.
    expect(find.widgetWithText(StatTile, '2'), findsOneWidget);
    expect(find.widgetWithText(StatTile, '48'), findsOneWidget);

    // The two part-graded assignments are queued; the handed-back ones are not.
    expect(find.text('Book Talk: Of Mice and Men'), findsOneWidget);
    expect(find.text('Cell Structure Presentation'), findsOneWidget);
    expect(find.text('Enzyme Activity Lab'), findsNothing);
    expect(find.text('Persuasive Essay: School Uniforms'), findsNothing);
    // 9 complete + 1 missing of 24 in each.
    expect(find.text('10 of 24 graded'), findsNWidgets(2));
    expect(find.byType(RubricProgressBar), findsNWidgets(2));

    // Not yet due, soonest first.
    final photosynthesis = tester.getTopLeft(find.text('Photosynthesis Lab'));
    final analysis = tester.getTopLeft(find.text('Literary Analysis Essay'));
    expect(photosynthesis.dy, lessThan(analysis.dy));

    expect(find.text('Oral Presentation'), findsOneWidget);

    await tester.ensureVisible(find.text('Book Talk: Of Mice and Men'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Talk: Of Mice and Men'));
    await tester.pumpAndSettle();
    expect(app.visited, [
      Routes.assignment(
        'sample-course-english10',
        'sample-assignment-book-talk',
      ),
    ]);
  });

  testWidgets('new assignment asks which class when there are several', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const HomePage(),
      overrides: [clock],
      seed: (db) => loadSampleData(db, now: _now),
    );
    await tester.ensureVisible(find.text('New assignment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New assignment'));
    await tester.pumpAndSettle();
    expect(find.text('Which class?'), findsOneWidget);

    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.newAssignment('sample-course-biology')]);
  });

  testWidgets('a class with nothing to grade reads as caught up', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: [clock],
      seed: (db) =>
          CourseRepository(db)
              .saveCourse(Course(id: 'c', name: 'Chemistry', createdAt: _now)),
    );
    expect(find.text('All caught up'), findsOneWidget);
    expect(find.text('New assignment'), findsOneWidget);
  });

  testWidgets('a brand-new teacher sees the empty state and its CTAs', (
    tester,
  ) async {
    final app = await pumpPage(tester, const HomePage(), overrides: [clock]);

    expect(find.text('Welcome to Rubric'), findsOneWidget);
    expect(find.text('Create a class'), findsOneWidget);
    expect(find.text('Build a rubric'), findsOneWidget);
    expect(find.text('To grade'.toUpperCase()), findsNothing);

    await tester.ensureVisible(find.text('Build a rubric'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build a rubric'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.buildRubric('new')]);
  });

  testWidgets('loading sample data from the empty state fills the dashboard', (
    tester,
  ) async {
    await pumpPage(tester, const HomePage(), overrides: [clock]);

    await tester.ensureVisible(find.text('Load sample data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load sample data'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Rubric'), findsNothing);
    expect(find.text('Book Talk: Of Mice and Men'), findsOneWidget);
  });

  testWidgets('tablet content is capped at a readable width', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: [clock],
      size: const Size(1366, 1024),
      seed: (db) => loadSampleData(db, now: _now),
    );
    final card = tester.getSize(
      find
          .ancestor(
            of: find.text('Book Talk: Of Mice and Men'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.width, lessThanOrEqualTo(HomePage.maxContentWidth));
  });
}
