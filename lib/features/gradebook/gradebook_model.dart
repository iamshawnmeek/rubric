import 'package:collection/collection.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/domain/stats.dart';

// Every number the gradebook, its analytics and the student profile show is
// computed here, on top of Scoring/Summary, so widgets only format.
//
// The rules:
// * A cell's grade is the grade of record from [Scoring.score].
// * Excused and not-yet-graded cells are left out of every average.
// * Missing work counts as 0 unless the teacher entered a score for it.
// * A student's course average is the mean of their graded assignments, each
//   weighted equally regardless of points possible.

/// What a gradebook cell is showing, independent of its number.
enum CellStatus {
  /// Fully scored (or overridden).
  graded,

  /// Partially scored; the running grade counts.
  inProgress,

  /// Not handed in. Counts as 0 unless scored.
  missing,

  /// Left out of every average.
  excused,

  /// No grade yet; left out of every average.
  notGraded,
}

/// One student × assignment intersection.
class GradeCell {
  const new({
    required this.assignment,
    required this.studentId,
    required this.status,
    this.evaluation,
    this.result,
  });

  factory of(Assignment assignment, String studentId, Evaluation? evaluation) {
    if (evaluation == null) {
      return GradeCell(
        assignment: assignment,
        studentId: studentId,
        status: CellStatus.notGraded,
      );
    }
    final result = Scoring.score(assignment.rubric, evaluation);
    final status = switch (evaluation.status) {
      EvaluationStatus.excused => CellStatus.excused,
      EvaluationStatus.missing => CellStatus.missing,
      _ when result.percent == null => CellStatus.notGraded,
      _
          when result.isComplete ||
              evaluation.overridePercent != null ||
              evaluation.status == EvaluationStatus.complete =>
        CellStatus.graded,
      _ => CellStatus.inProgress,
    };
    return GradeCell(
      assignment: assignment,
      studentId: studentId,
      status: status,
      evaluation: evaluation,
      result: result,
    );
  }

  final Assignment assignment;
  final String studentId;
  final CellStatus status;
  final Evaluation? evaluation;
  final ScoreResult? result;

  /// The grade of record, or null when this cell does not count.
  double? get percent => result?.percent;
  String? get letter => result?.letter;

  /// Whether this cell contributes to averages.
  bool get counts => percent != null;
}

/// A student's line in the gradebook.
class GradebookRow {
  const new({required this.student, required this.cells});

  final Student student;

  /// In the gradebook's assignment order.
  final List<GradeCell> cells;

  List<double> get _percents => [
    for (final c in cells)
      if (c.percent != null) c.percent!,
  ];

  /// Mean of graded assignments, equally weighted; null when none.
  double? get average {
    final values = _percents;
    return values.isEmpty ? null : values.average;
  }

  int get missingCount =>
      cells.where((c) => c.status == CellStatus.missing).length;

  int get gradedCount => _percents.length;

  /// How far the average fell with the most recent graded assignment: the
  /// average before it minus the average after it. Positive means a drop;
  /// null with fewer than two graded assignments.
  double? get latestDrop {
    final values = _percents;
    if (values.length < 2) return null;
    final before = values.sublist(0, values.length - 1).average;
    return before - values.average;
  }

  GradeCell cellFor(String assignmentId) =>
      cells.firstWhere((c) => c.assignment.id == assignmentId);
}

/// The two ways a gradebook can be ordered.
enum GradebookSort { name, average }

/// A course's students × assignments grid with every aggregate it needs.
class Gradebook {
  const new({
    required this.assignments,
    required this.rows,
    required this.scale,
  });

  /// Builds the grid. Evaluations for students not in [students] or
  /// assignments not in [assignments] are ignored.
  factory build({
    required Iterable<Student> students,
    required Iterable<Assignment> assignments,
    required Iterable<Evaluation> evaluations,
  }) {
    final ordered = chronological(assignments);
    final byKey = <(String, String), Evaluation>{
      for (final e in evaluations) (e.studentId, e.assignmentId): e,
    };
    final rows = [
      for (final s in students.sorted(compareStudents))
        GradebookRow(
          student: s,
          cells: [
            for (final a in ordered) GradeCell.of(a, s.id, byKey[(s.id, a.id)]),
          ],
        ),
    ];
    return Gradebook(
      assignments: ordered,
      rows: rows,
      scale: courseScale(ordered),
    );
  }

  /// Oldest first: by due date, falling back to when it was created.
  final List<Assignment> assignments;

  /// Sorted by name.
  final List<GradebookRow> rows;

  /// The scale course averages are lettered with.
  final GradingScale scale;

  bool get isEmpty => rows.isEmpty || assignments.isEmpty;

  GradebookRow? rowFor(String studentId) =>
      rows.firstWhereOrNull((r) => r.student.id == studentId);

  List<GradeCell> column(String assignmentId) => [
    for (final r in rows) r.cellFor(assignmentId),
  ];

  /// Class statistics for one assignment over the cells that count.
  Summary summaryFor(String assignmentId) => Summary.of(
    column(assignmentId).map((c) => c.percent).whereType<double>(),
  );

  /// Every student's course average, where they have one.
  List<double> get studentAverages =>
      rows.map((r) => r.average).whereType<double>().toList();

  /// Mean of student averages.
  double? get classAverage => Summary.of(studentAverages).mean;

  String? letterFor(double? percent) =>
      percent == null ? null : scale.letterFor(percent);

  /// [rows] in the requested order. Average sorts highest first by default,
  /// with students who have no average last either way; ties fall back to
  /// name.
  List<GradebookRow> sorted(GradebookSort sort, {bool descending = false}) {
    int byName(GradebookRow a, GradebookRow b) =>
        compareStudents(a.student, b.student);
    return switch (sort) {
      GradebookSort.name => rows.sorted(
        (a, b) => descending ? byName(b, a) : byName(a, b),
      ),
      GradebookSort.average => rows.sorted((a, b) {
        final x = a.average;
        final y = b.average;
        if (x == null || y == null) {
          if (x == y) return byName(a, b);
          return x == null ? 1 : -1;
        }
        final c = descending ? x.compareTo(y) : y.compareTo(x);
        return c != 0 ? c : byName(a, b);
      }),
    };
  }

  /// Class mean per assignment over time, skipping assignments nobody has a
  /// grade on yet.
  List<TrendPoint> get classTrend => [
    for (final a in assignments)
      if (summaryFor(a.id).mean case final mean?)
        TrendPoint(assignment: a, percent: mean),
  ];

  /// One student's grades over time.
  List<TrendPoint> studentTrend(String studentId) => [
    for (final c in rowFor(studentId)?.cells ?? const <GradeCell>[])
      if (c.percent case final p?)
        TrendPoint(assignment: c.assignment, percent: p),
  ];
}

class TrendPoint {
  const new({required this.assignment, required this.percent});

  final Assignment assignment;
  final double percent;
}

/// When an assignment sits on the timeline.
DateTime assignmentDate(Assignment a) => a.dueDate ?? a.createdAt;

List<Assignment> chronological(Iterable<Assignment> assignments) =>
    assignments.sorted((a, b) {
      final c = assignmentDate(a).compareTo(assignmentDate(b));
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });

/// The scale most of the course's assignments use; ties go to the most
/// recent assignment's. [GradingScale.standard] for a course with none.
GradingScale courseScale(List<Assignment> chronological) {
  if (chronological.isEmpty) return GradingScale.standard;
  final counts = <GradingScale, int>{};
  for (final a in chronological) {
    counts.update(a.rubric.scale, (c) => c + 1, ifAbsent: () => 1);
  }
  final top = counts.values.max;
  return chronological.reversed
      .map((a) => a.rubric.scale)
      .firstWhere((s) => counts[s] == top);
}

/// Counts of [values] in [bins] equal-width buckets over 0–100. The last
/// bucket is closed, so 100 lands in 90–100.
List<int> histogram(Iterable<double> values, {int bins = 10}) {
  final counts = List.filled(bins, 0);
  final width = 100 / bins;
  for (final v in values) {
    final i = (v.clamp(0, 100) / width).floor().clamp(0, bins - 1);
    counts[i]++;
  }
  return counts;
}

/// How many of [values] earn each letter in [scale], highest letter first,
/// including letters nobody earned.
Map<String, int> letterDistribution(
  Iterable<double> values,
  GradingScale scale,
) {
  final counts = {for (final b in scale.bands) b.letter: 0};
  for (final v in values) {
    counts.update(scale.letterFor(v), (c) => c + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// Five coarse bands for tinting grades and heat-map cells: 4 is 90+, 3 is
/// 80+, 2 is 70+, 1 is 60+, 0 below. Percent-based so it reads the same
/// whatever letter scale an assignment uses.
int gradeTier(double percent) => switch (percent) {
  >= 90 => 4,
  >= 80 => 3,
  >= 70 => 2,
  >= 60 => 1,
  _ => 0,
};

// ---- Needs attention -------------------------------------------------------

/// Why a student is flagged.
class AttentionItem {
  const new({required this.row, required this.missing, this.drop});

  final GradebookRow row;
  final int missing;

  /// Points the average fell with the latest assignment, when that is why.
  final double? drop;
}

/// Students with at least [missingThreshold] missing assignments, or whose
/// average fell by at least [dropThreshold] points with their latest graded
/// assignment. Most missing first, then biggest drop.
List<AttentionItem> needsAttention(
  Gradebook gradebook, {
  int missingThreshold = 2,
  double dropThreshold = 5,
}) {
  final items = <AttentionItem>[];
  for (final row in gradebook.rows) {
    final missing = row.missingCount;
    final drop = row.latestDrop;
    final dropped = drop != null && drop >= dropThreshold - 1e-9;
    if (missing >= missingThreshold || dropped) {
      items.add(
        AttentionItem(row: row, missing: missing, drop: dropped ? drop : null),
      );
    }
  }
  return items.sorted((a, b) {
    final c = b.missing.compareTo(a.missing);
    if (c != 0) return c;
    final d = (b.drop ?? 0).compareTo(a.drop ?? 0);
    return d != 0 ? d : compareStudents(a.row.student, b.row.student);
  });
}

// ---- Objectives ------------------------------------------------------------

/// Objectives are matched across assignments by title (trimmed, case
/// ignored): each assignment grades against its own rubric snapshot, so the
/// same skill can carry different ids in different assignments.
String objectiveKey(String title) => title.trim().toLowerCase();

/// Per-assignment objective percents for one cell, merged by [objectiveKey].
Map<String, double> _objectiveValues(GradeCell cell) {
  final result = cell.result;
  if (result == null || !cell.counts) return const {};
  final byKey = <String, List<double>>{};
  for (final o in cell.assignment.rubric.objectives) {
    final p = result.objectivePercents[o.id];
    if (p != null) byKey.putIfAbsent(objectiveKey(o.title), () => []).add(p);
  }
  return byKey.map((k, v) => MapEntry(k, v.average));
}

/// One objective's class mean in each assignment that grades it.
class ObjectiveMastery {
  const new({required this.title, required this.means});

  final String title;

  /// Assignment id → class mean. Only assignments whose rubric includes this
  /// objective appear; a null value means it is in the rubric but ungraded.
  final Map<String, double?> means;

  /// Mean of the per-assignment means, each assignment weighted equally.
  double? get overall {
    final values = means.values.whereType<double>();
    return values.isEmpty ? null : values.average;
  }
}

/// Every objective in the course, in the order they first appear.
List<ObjectiveMastery> objectiveMastery(Gradebook gradebook) {
  final titles = <String, String>{};
  final means = <String, Map<String, double?>>{};
  for (final a in gradebook.assignments) {
    final values = <String, List<double>>{};
    for (final o in a.rubric.objectives) {
      final key = objectiveKey(o.title);
      titles.putIfAbsent(key, o.title.trim);
      values.putIfAbsent(key, () => []);
    }
    for (final cell in gradebook.column(a.id)) {
      for (final e in _objectiveValues(cell).entries) {
        values[e.key]!.add(e.value);
      }
    }
    for (final e in values.entries) {
      means.putIfAbsent(e.key, () => {})[a.id] = e.value.isEmpty
          ? null
          : e.value.average;
    }
  }
  return [
    for (final e in titles.entries)
      ObjectiveMastery(title: e.value, means: means[e.key]!),
  ];
}

/// A student's mean on one objective against the class's on the same work.
class ObjectiveComparison {
  const new({
    required this.title,
    required this.student,
    required this.classMean,
  });

  final String title;
  final double student;
  final double classMean;

  /// Positive when the student is ahead of the class.
  double get delta => student - classMean;
}

/// The student's objectives compared with the class, strongest first. Each
/// comparison uses only the assignments where the student has a mark on that
/// objective, so the class figure covers the same work.
List<ObjectiveComparison> studentObjectives(
  Gradebook gradebook,
  String studentId,
) {
  final row = gradebook.rowFor(studentId);
  if (row == null) return const [];
  final mastery = {
    for (final m in objectiveMastery(gradebook)) objectiveKey(m.title): m,
  };
  final mine = <String, List<double>>{};
  final theirs = <String, List<double>>{};
  for (final cell in row.cells) {
    for (final e in _objectiveValues(cell).entries) {
      final classMean = mastery[e.key]?.means[cell.assignment.id];
      if (classMean == null) continue;
      mine.putIfAbsent(e.key, () => []).add(e.value);
      theirs.putIfAbsent(e.key, () => []).add(classMean);
    }
  }
  return [
    for (final key in mine.keys)
      ObjectiveComparison(
        title: mastery[key]!.title,
        student: mine[key]!.average,
        classMean: theirs[key]!.average,
      ),
  ].sorted((a, b) => b.delta.compareTo(a.delta));
}
