import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/features/grading/grading_logic.dart';

import '../../helpers/db.dart';
import 'grading_seed.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  const args = (assignmentId: 'a1', studentId: 's-ada');
  final opened = <GradingArgs>[];

  Future<GradingController> open({
    List<Evaluation> evaluations = const [],
    GradingArgs at = args,
  }) async {
    await seedGrading(db, evaluations: evaluations);
    opened.add(at);
    container.listen(gradingControllerProvider(at), (_, _) {});
    await container.read(gradingControllerProvider(at).future);
    return await container.read(gradingControllerProvider(at).notifier);
  }

  GradingSession session([GradingArgs at = args]) =>
      container.read(gradingControllerProvider(at)).requireValue;

  Future<Evaluation?> stored(String studentId) =>
      AssignmentRepository(db).getEvaluation('a1', studentId);

  setUp(() {
    db = testDatabase();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    // Land every pending save before the db closes; the dispose-time flush
    // is fire-and-forget.
    for (final a in opened) {
      await container.read(gradingControllerProvider(a).notifier).flush();
    }
    opened.clear();
    await pumpEventQueue();
    container.dispose();
    await db.close();
  });

  test('loads the active roster in compareStudents order', () async {
    await open();
    expect(session().students.map((s) => s.id), rosterOrder);
    expect(session().current!.id, 's-ada');
    expect(session().index, 0);
  });

  test('an unknown student id opens on the first student', () async {
    await open(at: (assignmentId: 'a1', studentId: 'nobody'));
    expect(
      session((assignmentId: 'a1', studentId: 'nobody')).currentStudentId,
      's-ada',
    );
  });

  test('a missing assignment errors with GradingAssignmentMissing', () async {
    const gone = (assignmentId: 'nope', studentId: 's-ada');
    container.listen(gradingControllerProvider(gone), (_, _) {});
    await expectLater(
      container.read(gradingControllerProvider(gone).future),
      throwsA(isA<GradingAssignmentMissing>()),
    );
  });

  test('an edit updates the live grade at once and saves after the '
      'debounce, with the derived status', () async {
    final c = await open();
    c.edit((r, e) => GradingLogic.setScore(r, e, 'o1', const PercentScore(80)));
    expect(session().result.percent, 80);
    expect(await stored('s-ada'), isNull, reason: 'debounced, not yet saved');

    await Future<void>.delayed(
      GradingController.saveDelay + const Duration(milliseconds: 100),
    );
    final saved = await stored('s-ada');
    expect(saved!.scores['o1'], const PercentScore(80));
    expect(saved.status, EvaluationStatus.inProgress);
  });

  test('moving to another student saves immediately', () async {
    final c = await open();
    c.edit((r, e) => GradingLogic.setScore(r, e, 'o1', const PercentScore(70)));
    expect(c.step(forward: true), isTrue);
    await pumpEventQueue();
    expect((await stored('s-ada'))!.scores['o1'], const PercentScore(70));
    expect(session().current!.id, 's-bob');
  });

  test('step stops at the ends of the roster', () async {
    final c = await open();
    expect(c.step(forward: false), isFalse);
    c.goTo('s-cara');
    expect(c.step(forward: true), isFalse);
    expect(c.step(forward: false), isTrue);
    expect(session().current!.id, 's-alan');
  });

  test('undo reverts one step; coalesced edits undo together', () async {
    final c = await open();
    c
      ..edit(
        (r, e) => GradingLogic.setScore(r, e, 'o1', const PercentScore(90)),
      )
      ..edit((_, e) => GradingLogic.setComment(e, 'G'), coalesce: 'comment')
      ..edit((_, e) => GradingLogic.setComment(e, 'Go'), coalesce: 'comment')
      ..edit((_, e) => GradingLogic.setComment(e, 'Good'), coalesce: 'comment');
    expect(session().undo, hasLength(2));

    c.undo();
    expect(session().evaluation.comment, '');
    expect(session().evaluation.scores['o1'], const PercentScore(90));
    c.undo();
    expect(session().evaluation.scores, isEmpty);
    expect(session().canUndo, isFalse);

    await c.flush();
    expect((await stored('s-ada'))!.scores, isEmpty);
  });

  test('undo switches back to the student the change was made on', () async {
    final c = await open();
    c
      ..edit((r, e) => GradingLogic.setMissing(r, e, missing: true))
      ..goTo('s-alan')
      ..undo();
    expect(session().current!.id, 's-ada');
    expect(session().evaluation.status, EvaluationStatus.notStarted);
  });

  test('nextUngraded skips graded students, then shows finished with the '
      'class average', () async {
    final c = await open(
      evaluations: [gradedEval('s-bob', 90), gradedEval('s-alan', 70)],
    );
    c.nextUngraded();
    expect(session().current!.id, 's-cara');

    c
      ..edit((r, e) => GradingLogic.setExcused(r, e, excused: true))
      ..nextUngraded();
    expect(session().current!.id, 's-ada');
    expect(session().finished, isFalse);

    for (final o in ['o1', 'o2', 'o3']) {
      c.edit((r, e) => GradingLogic.setScore(r, e, o, const PercentScore(80)));
    }
    c.nextUngraded();
    expect(session().finished, isTrue);
    expect(session().allGraded, isTrue);
    // Ada 80, Bob 90, Alan 70; Cara excused.
    expect(session().classAverage, closeTo(80, 1e-9));
  });
}
