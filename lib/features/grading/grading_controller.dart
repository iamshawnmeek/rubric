import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncNotifierProviderFamily;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/features/grading/grading_logic.dart';

typedef GradingArgs = ({String assignmentId, String studentId});

/// Thrown by the controller when the assignment it was opened for is gone.
class GradingAssignmentMissing implements Exception {
  const new();
}

/// One step back: the student it happened to and what their evaluation was.
typedef GradingUndo = ({String studentId, Evaluation before, String? key});

/// Everything the grading screen shows. Immutable; the controller replaces it.
class GradingSession {
  const new({
    required this.assignment,
    required this.students,
    required this.evaluations,
    required this.currentStudentId,
    this.undo = const [],
    this.finished = false,
  });

  final Assignment assignment;

  /// Active roster in [compareStudents] order.
  final List<Student> students;

  /// Keyed by student id. Students not yet touched have no entry.
  final Map<String, Evaluation> evaluations;
  final String currentStudentId;
  final List<GradingUndo> undo;

  /// True once "next ungraded" found nobody left.
  final bool finished;

  Rubric get rubric => assignment.rubric;
  Student? get current =>
      students.firstWhereOrNull((s) => s.id == currentStudentId);
  int get index => students.indexWhere((s) => s.id == currentStudentId);
  bool get canUndo => undo.isNotEmpty;

  /// The current student's evaluation, or a blank one if never touched.
  Evaluation get evaluation => evaluationOf(currentStudentId);

  Evaluation evaluationOf(String studentId) =>
      evaluations[studentId] ??
      Evaluation(
        id: '',
        assignmentId: assignment.id,
        studentId: studentId,
        updatedAt: assignment.createdAt,
      );

  ScoreResult get result => Scoring.score(rubric, evaluation);

  bool isGraded(String studentId) =>
      GradingLogic.isGraded(rubric, evaluations[studentId]);

  int get gradedCount => students.where((s) => isGraded(s.id)).length;
  bool get allGraded => GradingLogic.allGraded(rubric, students, evaluations);
  double? get classAverage =>
      GradingLogic.classAverage(rubric, students, evaluations);

  GradingSession copyWith({
    Map<String, Evaluation>? evaluations,
    String? currentStudentId,
    List<GradingUndo>? undo,
    bool? finished,
  }) => GradingSession(
    assignment: assignment,
    students: students,
    evaluations: evaluations ?? this.evaluations,
    currentStudentId: currentStudentId ?? this.currentStudentId,
    undo: undo ?? this.undo,
    finished: finished ?? this.finished,
  );
}

final AsyncNotifierProviderFamily<
  GradingController,
  GradingSession,
  GradingArgs
>
gradingControllerProvider = AsyncNotifierProvider.autoDispose
    .family<GradingController, GradingSession, GradingArgs>(
      GradingController.new,
      // A deleted assignment will not reappear by retrying.
      retry: (_, _) => null,
    );

/// Holds the grading session for one assignment. Edits apply instantly to
/// state and are written through [AssignmentRepository.saveEvaluation] after
/// [saveDelay] of quiet, and immediately when the teacher changes student or
/// leaves the screen.
class GradingController extends AsyncNotifier<GradingSession> {
  new(this.args);

  final GradingArgs args;

  static const saveDelay = Duration(milliseconds: 400);
  static const _undoLimit = 50;

  Timer? _saveTimer;
  final _dirty = <String>{};

  // Kept outside `state`/`ref` so the final flush can still run while the
  // provider is being disposed, when neither may be touched.
  late AssignmentRepository _repo;
  GradingSession? _latest;

  @override
  Future<GradingSession> build() async {
    ref.onDispose(() {
      _saveTimer?.cancel();
      unawaited(flush());
    });
    final assignments = _repo = ref.read(assignmentRepositoryProvider);
    final assignment = await assignments.get(args.assignmentId);
    if (assignment == null) throw const GradingAssignmentMissing();
    final students = await ref
        .read(courseRepositoryProvider)
        .students(assignment.courseId);
    final evaluations = await assignments.evaluations(assignment.id);
    final current = students.any((s) => s.id == args.studentId)
        ? args.studentId
        : students.firstOrNull?.id ?? args.studentId;
    return _latest = GradingSession(
      assignment: assignment,
      students: students,
      evaluations: {for (final e in evaluations) e.studentId: e},
      currentStudentId: current,
    );
  }

  GradingSession? get _session => _latest;

  void _set(GradingSession s) => state = AsyncData(_latest = s);

  /// Applies [change] to the current student's evaluation.
  ///
  /// Consecutive edits with the same non-null [coalesce] key (typing in one
  /// field, dragging one slider) share a single undo step.
  void edit(
    Evaluation Function(Rubric rubric, Evaluation e) change, {
    String? coalesce,
  }) {
    final s = _session;
    if (s == null) return;
    final id = s.currentStudentId;
    final before =
        s.evaluations[id] ??
        Evaluation.start(assignmentId: s.assignment.id, studentId: id);
    final after = change(s.rubric, before);
    if (after == before) return;

    final top = s.undo.lastOrNull;
    final merge =
        coalesce != null && top?.key == coalesce && top?.studentId == id;
    final undo = merge
        ? s.undo
        : [
            ...s.undo.skip(s.undo.length >= _undoLimit ? 1 : 0),
            (studentId: id, before: before, key: coalesce),
          ];
    _set(
      s.copyWith(
        evaluations: {...s.evaluations, id: after},
        undo: undo,
        finished: false,
      ),
    );
    _markDirty(id);
  }

  /// Reverts the most recent change, switching to that student if needed.
  void undo() {
    final s = _session;
    final last = s?.undo.lastOrNull;
    if (s == null || last == null) return;
    _set(
      s.copyWith(
        evaluations: {...s.evaluations, last.studentId: last.before},
        currentStudentId: last.studentId,
        undo: s.undo.sublist(0, s.undo.length - 1),
        finished: false,
      ),
    );
    _markDirty(last.studentId);
  }

  void goTo(String studentId) {
    final s = _session;
    if (s == null || !s.students.any((st) => st.id == studentId)) return;
    unawaited(flush());
    _set(s.copyWith(currentStudentId: studentId, finished: false));
  }

  /// Moves one student along the roster; false at either end.
  bool step({required bool forward}) {
    final s = _session;
    if (s == null) return false;
    final id = GradingLogic.neighbour(
      s.students,
      s.currentStudentId,
      forward: forward,
    );
    if (id == null) return false;
    goTo(id);
    return true;
  }

  /// Jumps to the next ungraded student, or shows the finished state when
  /// there is none.
  void nextUngraded() {
    final s = _session;
    if (s == null) return;
    final id = GradingLogic.nextUngraded(
      s.rubric,
      s.students,
      s.evaluations,
      s.currentStudentId,
    );
    if (id == null) {
      unawaited(flush());
      _set(s.copyWith(finished: true));
    } else {
      goTo(id);
    }
  }

  void dismissFinished() {
    final s = _session;
    if (s != null) _set(s.copyWith(finished: false));
  }

  /// Writes every unsaved evaluation now.
  Future<void> flush() async {
    _saveTimer?.cancel();
    final s = _session;
    if (s == null || _dirty.isEmpty) return;
    final toSave = [for (final id in _dirty) ?s.evaluations[id]];
    _dirty.clear();
    await _repo.saveEvaluations(toSave);
  }

  void _markDirty(String studentId) {
    _dirty.add(studentId);
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }
}
