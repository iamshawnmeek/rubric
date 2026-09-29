import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubrics/rubric_detail_page.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fixtures.dart';

const tall = Size(390, 2600);

Future<void> seedEssay(
  AppDatabase db, {
  GradingMode mode = GradingMode.simple,
}) => RubricRepository(db).save(essayRubric(mode: mode), now: t0);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('renders groups, weights, objectives and the grading scale', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      seed: seedEssay,
      size: tall,
    );
    expect(find.text('Essay'), findsOneWidget);
    expect(find.text('Writing'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    for (final objective in ['Grammar', 'Organization', 'Sources']) {
      expect(find.text(objective), findsOneWidget);
    }
    expect(find.text('90% to 100%'), findsOneWidget);
    expect(find.text('0% to 59.9%'), findsOneWidget);
    expect(find.text('Not used in any assignments yet'), findsOneWidget);
    // Simple rubrics have no ladder.
    expect(find.text('PERFORMANCE LEVELS'), findsNothing);
  });

  testWidgets('detailed rubrics show the ladder and descriptor grid', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      seed: (db) => seedEssay(db, mode: GradingMode.detailed),
      size: tall,
    );
    expect(find.text('PERFORMANCE LEVELS'), findsOneWidget);
    expect(find.text('Exemplary'), findsNWidgets(2)); // ladder + grid header
    expect(find.text('4 pts'), findsNWidgets(2));
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Flawless'), findsOneWidget);
    // Grammar has one descriptor of four; the other objectives none.
    expect(find.text('Not described'), findsNWidgets(3 * 4 - 1));
  });

  testWidgets('shows how many assignments use it', (tester) async {
    await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      size: tall,
      seed: (db) async {
        await seedEssay(db);
        final course = Course.create(name: 'English 10', now: t0);
        await CourseRepository(db).saveCourse(course);
        for (final title in ['Essay 1', 'Essay 2', 'Essay 3']) {
          await AssignmentRepository(db).save(
            Assignment.create(
              courseId: course.id,
              title: title,
              rubric: essayRubric(),
              now: t0,
            ),
          );
        }
      },
    );
    expect(find.text('Used in 3 assignments'), findsOneWidget);
  });

  testWidgets('an unfinished rubric lists what is missing', (tester) async {
    await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      size: tall,
      seed: (db) => RubricRepository(db).save(
        essayRubric().copyWith(
          groups: [essayRubric().groups.first.copyWith(weight: 50)],
        ),
      ),
    );
    expect(
      find.text('Finish this rubric before grading with it'),
      findsOneWidget,
    );
    expect(find.text('•  Group weights must add up to 100%.'), findsOneWidget);
  });

  testWidgets('Edit opens the builder', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      seed: seedEssay,
    );
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(app.visited.single, startsWith('/build/r1'));
  });

  testWidgets('Use in Assignment goes to Classes', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      seed: seedEssay,
    );
    await tester.tap(find.text('Use in Assignment'));
    await tester.pumpAndSettle();
    expect(app.visited, ['/classes']);
  });

  testWidgets('Duplicate from the menu adds a copy', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      seed: seedEssay,
    );
    await tester.tap(find.byTooltip('More actions for Essay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await settle(tester);
    final all = (await tester.runAsync(() => RubricRepository(app.db).all()))!;
    expect(all.map((r) => r.title), containsAll(['Essay', 'Essay (copy)']));
  });

  testWidgets('Delete removes the rubric and leaves the page', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'r1'),
      seed: seedEssay,
    );
    await tester.tap(find.byTooltip('More actions for Essay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(
      await tester.runAsync(() => RubricRepository(app.db).get('r1')),
      isNull,
    );
    expect(app.visited, ['/rubrics']);
  });

  testWidgets('a missing rubric says so', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricDetailPage(rubricId: 'gone'),
    );
    expect(find.text('Rubric not found'), findsOneWidget);
    await tester.tap(find.text('Back to rubrics'));
    await tester.pumpAndSettle();
    expect(app.visited, ['/rubrics']);
  });
}
