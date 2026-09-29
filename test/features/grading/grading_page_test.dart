import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/features/grading/grading_page.dart';
import 'package:rubric/features/grading/widgets/student_list_pane.dart';

import '../../helpers/app_harness.dart';
import 'grading_seed.dart';

const _page = GradingPage(assignmentId: 'a1', studentId: 's-ada');

Finder _inObjective(String studentId, String objectiveId, Finder f) =>
    find.descendant(
      of: find.byKey(ValueKey('objective-$studentId-$objectiveId')),
      matching: f,
    );

String _liveGrade(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('grading-live-grade'))).data!;

/// Waits out the save debounce and lets the write land.
Future<void> _settleSave(WidgetTester tester) async {
  await tester.pump(GradingController.saveDelay);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<Evaluation?> _stored(WidgetTester tester, TestApp app, String id) =>
    tester
        .runAsync(() => AssignmentRepository(app.db).getEvaluation('a1', id))
        .then((e) => e);

/// Scrolls the grading page until [f] is built, then centres it so the
/// pinned grade summary cannot cover it.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(f, 200, scrollable: scrollable);
    } on Object {
      await tester.scrollUntilVisible(f, -200, scrollable: scrollable);
    }
  }
  await tester.runAsync(
    () => Scrollable.ensureVisible(tester.element(f), alignment: .5),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await _reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _commentField() => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.hintText == 'Write feedback for this student',
);

void main() {
  testWidgets('simple rubric: quick picks update the live grade and '
      'persist with the derived status', (tester) async {
    final app = await pumpPage(tester, _page, seed: seedGrading);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('1 of 4'), findsOneWidget);
    expect(_liveGrade(tester), 'No grade yet');
    expect(find.text('Scored 0 of 3'), findsOneWidget);

    await _tapVisible(tester, _inObjective('s-ada', 'o1', find.text('90%')));
    expect(_liveGrade(tester), '90%');
    expect(find.text('Scored 1 of 3'), findsOneWidget);

    await _tapVisible(tester, _inObjective('s-ada', 'o2', find.text('70%')));
    await _tapVisible(tester, _inObjective('s-ada', 'o3', find.text('50%')));
    // Writing 80 (60%), Research 50 (40%) → 68, a D on the standard scale.
    expect(_liveGrade(tester), '68%');
    expect(find.byKey(const Key('grading-live-letter')), findsOneWidget);
    expect(find.text('Scored 3 of 3'), findsOneWidget);

    await _settleSave(tester);
    final saved = await _stored(tester, app, 's-ada');
    expect(saved!.scores, {
      'o1': const PercentScore(90),
      'o2': const PercentScore(70),
      'o3': const PercentScore(50),
    });
    expect(saved.status, EvaluationStatus.complete);
  });

  testWidgets('simple rubric: a typed percent sets the score', (tester) async {
    final app = await pumpPage(tester, _page, seed: seedGrading);
    final field = _inObjective('s-ada', 'o3', find.byType(TextField));
    await _reveal(tester, field);
    await tester.enterText(field, '85');
    await tester.pumpAndSettle();
    expect(_liveGrade(tester), '85%');
    await _settleSave(tester);
    expect(
      (await _stored(tester, app, 's-ada'))!.scores['o3'],
      const PercentScore(85),
    );
  });

  testWidgets('detailed rubric: tapping a level tile scores it, tapping '
      'again clears it', (tester) async {
    final app = await pumpPage(
      tester,
      _page,
      seed: (db) => seedGrading(db, mode: GradingMode.detailed),
    );
    // The objective's own descriptor is shown on its level tile.
    expect(_inObjective('s-ada', 'o1', find.text('Flawless')), findsOneWidget);

    final proficient = _inObjective('s-ada', 'o1', find.text('Proficient'));
    await _tapVisible(tester, proficient);
    // 3 of 4 points → 75%.
    expect(_liveGrade(tester), '75%');
    await _settleSave(tester);
    expect(
      (await _stored(tester, app, 's-ada'))!.scores['o1'],
      const LevelScore('L3'),
    );

    await _tapVisible(tester, proficient);
    expect(_liveGrade(tester), 'No grade yet');
    await _settleSave(tester);
    final cleared = await _stored(tester, app, 's-ada');
    expect(cleared!.scores, isEmpty);
    expect(cleared.status, EvaluationStatus.notStarted);
  });

  testWidgets('missing counts as zero; excused shows no grade', (tester) async {
    final app = await pumpPage(tester, _page, seed: seedGrading);

    await _tapVisible(tester, find.text('Missing'));
    expect(_liveGrade(tester), '0%');
    await _settleSave(tester);
    expect(
      (await _stored(tester, app, 's-ada'))!.status,
      EvaluationStatus.missing,
    );

    await _tapVisible(tester, find.text('Excused'));
    expect(_liveGrade(tester), 'Excused');
    expect(find.byKey(const Key('grading-live-letter')), findsNothing);
    await _settleSave(tester);
    expect(
      (await _stored(tester, app, 's-ada'))!.status,
      EvaluationStatus.excused,
    );
  });

  testWidgets('late applies the default penalty from settings', (tester) async {
    await pumpPage(tester, _page, seed: seedGrading);
    for (final o in ['o1', 'o2', 'o3']) {
      await _tapVisible(tester, _inObjective('s-ada', o, find.text('90%')));
    }
    expect(_liveGrade(tester), '90%');
    await _tapVisible(tester, find.text('Late'));
    expect(_liveGrade(tester), '80%');
    expect(find.text('Late penalty'), findsOneWidget);
    await _tapVisible(tester, find.text('Late'));
    expect(_liveGrade(tester), '90%');
    await _settleSave(tester);
  });

  testWidgets('undo reverts the last change', (tester) async {
    await pumpPage(tester, _page, seed: seedGrading);
    await _tapVisible(tester, _inObjective('s-ada', 'o1', find.text('60%')));
    expect(_liveGrade(tester), '60%');
    await _reveal(tester, find.byTooltip('Undo last change'));
    await tester.tap(find.byTooltip('Undo last change'));
    await tester.pumpAndSettle();
    expect(_liveGrade(tester), 'No grade yet');
    await _settleSave(tester);
  });

  testWidgets('next/previous walk the roster in compareStudents order', (
    tester,
  ) async {
    await pumpPage(tester, _page, seed: seedGrading);
    final names = <String>[];
    for (var i = 0; i < 4; i++) {
      names.add(
        [
          'Ada Lovelace',
          'Bob Lovelace',
          'Alan Turing',
          'Cara Zed',
        ].firstWhere((n) => find.text(n).evaluate().isNotEmpty),
      );
      await tester.tap(find.byTooltip('Next student'));
      await tester.pumpAndSettle();
    }
    expect(names, ['Ada Lovelace', 'Bob Lovelace', 'Alan Turing', 'Cara Zed']);
    // Next at the end stays put.
    expect(find.text('Cara Zed'), findsOneWidget);
    expect(find.textContaining('4 of 4'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous student'));
    await tester.pumpAndSettle();
    expect(find.text('Alan Turing'), findsOneWidget);
  });

  testWidgets('a horizontal swipe moves to the next student', (tester) async {
    await pumpPage(tester, _page, seed: seedGrading);
    await tester.fling(find.text('Ada Lovelace'), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Bob Lovelace'), findsOneWidget);
  });

  testWidgets('comment bank: inserting a snippet fills the comment and '
      'records the use', (tester) async {
    final app = await pumpPage(
      tester,
      _page,
      seed: (db) => seedGrading(
        db,
        snippets: const [
          CommentSnippet(id: 'k1', text: 'Strong thesis.', category: 'Praise'),
          CommentSnippet(id: 'k2', text: 'Cite your sources.'),
        ],
      ),
    );
    await _tapVisible(tester, find.text('Comment bank'));
    expect(find.text('Insert a comment'), findsOneWidget);

    // Search narrows the list.
    await tester.enterText(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      ),
      'cite',
    );
    await tester.pumpAndSettle();
    expect(find.text('Strong thesis.'), findsNothing);

    await tester.tap(find.text('Cite your sources.'));
    await tester.pumpAndSettle();
    expect(find.text('Insert a comment'), findsNothing);
    final field = _commentField();
    await _reveal(tester, field);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'Cite your sources.',
    );

    await _settleSave(tester);
    expect(
      (await _stored(tester, app, 's-ada'))!.comment,
      'Cite your sources.',
    );
    final snippets = await tester.runAsync(
      () => CommentRepository(app.db).all(),
    );
    expect(snippets!.firstWhere((s) => s.id == 'k2').useCount, 1);
  });

  testWidgets('comment bank: save this comment to the bank once', (
    tester,
  ) async {
    final app = await pumpPage(tester, _page, seed: seedGrading);
    final comment = _commentField();
    await _reveal(tester, comment);
    await tester.enterText(comment, 'Great use of evidence.');
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Save to bank'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Saved to your comment bank'), findsOneWidget);
    // Let the snackbar leave so it does not cover the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Save to bank'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Already in your comment bank'), findsOneWidget);

    final snippets = await tester.runAsync(
      () => CommentRepository(app.db).all(),
    );
    expect(snippets!.map((s) => s.text), ['Great use of evidence.']);
    await _settleSave(tester);
  });

  testWidgets('next ungraded skips graded students and ends on a finished '
      'state with the class average', (tester) async {
    await pumpPage(
      tester,
      _page,
      seed: (db) => seedGrading(
        db,
        evaluations: [
          gradedEval('s-bob', 90),
          gradedEval('s-alan', 70),
          gradedEval('s-cara', 80),
        ],
      ),
    );
    expect(find.text('Next ungraded'), findsOneWidget);
    await tester.tap(find.text('Next ungraded'));
    await tester.pumpAndSettle();
    // Only Ada is ungraded, and she is current: the jump stays on her.
    expect(find.text('Ada Lovelace'), findsOneWidget);

    for (final o in ['o1', 'o2', 'o3']) {
      await _tapVisible(tester, _inObjective('s-ada', o, find.text('100%')));
    }
    expect(find.text('Finish'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(find.text('Everyone’s graded'), findsOneWidget);
    expect(find.text('4 students graded.'), findsOneWidget);
    // (100 + 90 + 70 + 80) / 4 = 85.
    expect(
      find.descendant(
        of: find.byKey(const Key('grading-class-average')),
        matching: find.text('85%'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Back to assignment'));
    await tester.pumpAndSettle();
    expect(find.text('visited /classes/c1/assignments/a1'), findsOneWidget);
  });

  testWidgets('tablet shows the roster beside the rubric', (tester) async {
    await pumpPage(
      tester,
      _page,
      seed: seedGrading,
      size: const Size(1280, 900),
    );
    expect(find.byType(StudentListPane), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Alan Turing, Not graded'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 of 4'), findsOneWidget);
  });

  testWidgets('a deleted assignment shows a friendly empty state', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const GradingPage(assignmentId: 'gone', studentId: 's-ada'),
      seed: seedGrading,
    );
    expect(find.text('This assignment no longer exists'), findsOneWidget);
  });

  testWidgets('an empty class explains how to start', (tester) async {
    await pumpPage(
      tester,
      _page,
      seed: (db) => seedGrading(db, students: const []),
    );
    expect(find.text('No students in this class yet'), findsOneWidget);
  });
}
