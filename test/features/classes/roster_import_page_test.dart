import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/classes/roster_import_page.dart';

import '../../helpers/app_harness.dart';
import 'classes_seed.dart';

const _csv =
    '﻿Last Name,First Name,Student ID,Email\n'
    'Turing,Alan,1003,alan@school.org\n'
    '"Johnson",Katherine,1004,kj@school.org\n'
    'Lovelace,Ada,1001,ada@school.org\n'
    ',,1005,\n'
    'Turing,Alan,1003,alan@school.org\n';

/// Tall enough that the whole review list is built without scrolling.
const _tall = Size(390, 2400);

Future<void> _preview(WidgetTester tester, String csv) async {
  await tester.enterText(find.byType(TextField), csv);
  await tester.pump();
  await tester.tap(find.text('Preview'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pasted CSV is mapped, validated and imported', (tester) async {
    final app = await pumpPage(
      tester,
      const RosterImportPage(courseId: courseId),
      seed: seedBiology,
      size: _tall,
    );
    await _preview(tester, _csv);

    // Headers were recognised despite the BOM and a different column order.
    expect(find.text('First row is column names'), findsOneWidget);
    expect(find.text('Last Name'), findsOneWidget);
    expect(find.text('e.g. Turing'), findsOneWidget);

    // Every row is listed; only the clean ones are pre-selected.
    expect(find.text('Already in this class'), findsOneWidget);
    expect(find.text("No name, can't import"), findsOneWidget);
    expect(find.text('Repeats an earlier row'), findsOneWidget);
    expect(find.text('2 of 5 selected'), findsOneWidget);

    await tester.tap(find.text('Import 2 Students'));
    await tester.pumpAndSettle();

    final added = (await studentsIn(
      tester,
      app.db,
    )).where((s) => s.id != ada.id && s.id != grace.id).toList();
    expect(added.map((s) => s.sortName), [
      'Johnson, Katherine',
      'Turing, Alan',
    ]);
    expect(added.last.studentNumber, '1003');
    expect(added.last.email, 'alan@school.org');
    expect(app.visited, [Routes.course(courseId)]);
  });

  testWidgets('a flagged row can still be chosen deliberately', (tester) async {
    final app = await pumpPage(
      tester,
      const RosterImportPage(courseId: courseId),
      seed: seedBiology,
      size: _tall,
    );
    await _preview(tester, _csv);

    await tester.tap(find.text('Repeats an earlier row'));
    await tester.pump();
    expect(find.text('3 of 5 selected'), findsOneWidget);

    // The nameless row cannot be selected at all.
    await tester.tap(find.text("No name, can't import"));
    await tester.pump();
    expect(find.text('3 of 5 selected'), findsOneWidget);

    await tester.tap(find.text('Import 3 Students'));
    await tester.pumpAndSettle();
    expect(await studentsIn(tester, app.db), hasLength(5));
  });

  testWidgets('an unknown header can be switched on and remapped', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const RosterImportPage(courseId: courseId),
      seed: seedBiology,
      size: _tall,
    );
    // Headers the detector does not know: row one is read as a student.
    await _preview(tester, 'Pupil,Code\n"Turing, Alan",X9\n');
    expect(find.text('Import 2 Students'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Alan Turing'), findsOneWidget);
    expect(find.text('Import 1 Student'), findsOneWidget);

    // Unmapping the name column blocks the import and says why.
    await tester.tap(find.text('Pupil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't import"));
    await tester.pumpAndSettle();
    expect(find.text('Choose which column holds the student names.'), findsOne);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(await studentsIn(tester, app.db), hasLength(2));

    await tester.tap(find.text('Pupil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full name'));
    await tester.pumpAndSettle();
    // "X9" is ID-shaped, so Code was mapped to the student number for us.
    expect(find.text('Student #'), findsOneWidget);

    await tester.tap(find.text('Import 1 Student'));
    await tester.pumpAndSettle();
    final alan = (await studentsIn(
      tester,
      app.db,
    )).firstWhere((s) => s.firstName == 'Alan');
    expect(alan.lastName, 'Turing');
    expect(alan.studentNumber, 'X9');
  });

  testWidgets('Start over returns to the paste step', (tester) async {
    await pumpPage(
      tester,
      const RosterImportPage(courseId: courseId),
      seed: seedBiology,
      size: _tall,
    );
    await _preview(tester, _csv);
    await tester.tap(find.byType(BackChevron));
    await tester.pumpAndSettle();
    expect(find.text('Choose a CSV file'), findsOneWidget);
  });
}
