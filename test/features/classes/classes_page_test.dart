import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/features/classes/classes_page.dart';

import '../../helpers/app_harness.dart';
import 'classes_seed.dart';

void main() {
  testWidgets('an empty list invites creating the first class', (tester) async {
    await pumpPage(tester, const ClassesPage());
    expect(find.text('No classes yet'), findsOneWidget);
    expect(find.text('New Class'), findsOneWidget);
  });

  testWidgets('creating a class saves it and opens it', (tester) async {
    final app = await pumpPage(tester, const ClassesPage());

    await tester.tap(find.text('New Class'));
    await tester.pumpAndSettle();
    // Create stays disabled until the class has a name.
    await tester.tap(find.text('Create Class'));
    await tester.pumpAndSettle();
    expect(await allCourses(tester, app.db), isEmpty);

    await tester.enterText(field('e.g. Biology'), '  Chemistry ');
    await tester.enterText(field('e.g. Period 3'), 'Period 5');
    await tester.enterText(field('e.g. Fall 2026'), 'Spring 2027');
    await tester.pump();
    await tester.tap(find.text('Create Class'));
    await tester.pumpAndSettle();

    final course = (await allCourses(tester, app.db)).single;
    expect(course.name, 'Chemistry');
    expect(course.subtitle, 'Period 5 · Spring 2027');
    expect(app.visited, [Routes.course(course.id)]);
  });

  testWidgets('a class card shows section · term · students over the name', (
    tester,
  ) async {
    final app = await pumpPage(tester, const ClassesPage(), seed: seedBiology);
    expect(find.text('Period 3 · Fall 2026 · 2 students'), findsOneWidget);

    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.course(courseId)]);
  });

  testWidgets('archiving moves a class to the archived list', (tester) async {
    final app = await pumpPage(tester, const ClassesPage(), seed: seedBiology);

    await tester.tap(find.byTooltip('Actions for Biology'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Biology'), findsNothing);
    expect(find.text('Biology archived'), findsOneWidget);
    expect((await allCourses(tester, app.db)).single.archived, isTrue);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Biology'), findsOneWidget);
  });

  testWidgets('deleting an ungraded class states what goes with it', (
    tester,
  ) async {
    final app = await pumpPage(tester, const ClassesPage(), seed: seedBiology);

    await tester.tap(find.byTooltip('Actions for Biology'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Biology?'), findsOneWidget);
    expect(find.textContaining('its 2 students, its 0 assignments'), findsOne);
    expect(find.textContaining("can't be undone"), findsOneWidget);
    // No grades: no name to type.
    expect(find.textContaining('Type Biology to confirm'), findsNothing);

    await tester.tap(find.text('Delete Class'));
    await tester.pumpAndSettle();
    expect(await allCourses(tester, app.db), isEmpty);
    expect(await studentsIn(tester, app.db), isEmpty);
    expect(find.text('Biology deleted'), findsOneWidget);
  });

  testWidgets('deleting a class with grades requires typing its name', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const ClassesPage(),
      seed: (db) => seedBiology(db, graded: true),
    );

    await tester.tap(find.byTooltip('Actions for Biology'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('its 1 assignment and'), findsOneWidget);
    expect(
      find.text('This class has grades. Type Biology to confirm.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Delete Class'));
    await tester.pumpAndSettle();
    expect(await allCourses(tester, app.db), hasLength(1));

    await tester.enterText(find.byType(TextField), 'Biolog');
    await tester.pump();
    await tester.tap(find.text('Delete Class'));
    await tester.pumpAndSettle();
    expect(await allCourses(tester, app.db), hasLength(1));

    await tester.enterText(find.byType(TextField), 'biology ');
    await tester.pump();
    await tester.tap(find.text('Delete Class'));
    await tester.pumpAndSettle();
    expect(await allCourses(tester, app.db), isEmpty);
  });

  testWidgets('a class card is operable with a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await pumpPage(tester, const ClassesPage(), seed: seedBiology);

    final card = find.bySemanticsLabel(
      'Period 3 · Fall 2026 · 2 students, Biology',
    );
    expect(
      tester.getSemantics(card),
      matchesSemantics(
        label: 'Period 3 · Fall 2026 · 2 students, Biology',
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
        customActions: [
          const CustomSemanticsAction(label: 'Actions for Biology'),
        ],
      ),
    );
    tester.semantics.tap(
      find.semantics.byLabel('Period 3 · Fall 2026 · 2 students, Biology'),
    );
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.course(courseId)]);
    semantics.dispose();
  });

  testWidgets('content is capped at a readable width on tablets', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const ClassesPage(),
      seed: seedBiology,
      size: const Size(1366, 1024),
    );
    expect(tester.getSize(find.text('Biology')).width, lessThan(720));
    expect(
      tester.getTopLeft(find.text('Biology')).dx,
      greaterThan((1366 - 720) / 2),
    );
  });
}
