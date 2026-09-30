import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/sync_writer.dart';
import 'package:rubric/domain/classroom.dart';

class CourseRepository {
  /// [writer] defaults to local-only writes; the app passes its sync
  /// service so writes are also queued for the server.
  new(this._db, [SyncWriter? writer]) : _writer = writer ?? LocalWriter(_db);

  final AppDatabase _db;
  final SyncWriter _writer;

  static Map<String, Object?> courseToWire(Course c) => {
    'id': c.id,
    'name': c.name,
    'section': c.section,
    'term': c.term,
    'archived': c.archived,
    'created_on': c.createdAt.millisecondsSinceEpoch,
  };

  static Map<String, Object?> studentToWire(Student s) => {
    'id': s.id,
    'course_id': s.courseId,
    'first_name': s.firstName,
    'last_name': s.lastName,
    'student_number': s.studentNumber,
    'email': s.email,
    'notes': s.notes,
    'archived': s.archived,
  };

  static Course _course(CourseRow r) => Course(
    id: r.id,
    name: r.name,
    section: r.section,
    term: r.term,
    archived: r.archived,
    createdAt: r.createdAt,
  );

  static Student _student(StudentRow r) => Student(
    id: r.id,
    courseId: r.courseId,
    firstName: r.firstName,
    lastName: r.lastName,
    studentNumber: r.studentNumber,
    email: r.email,
    notes: r.notes,
    archived: r.archived,
  );

  Stream<List<Course>> watchCourses({bool archived = false}) {
    final q = _db.select(_db.courses)
      ..where((c) => c.archived.equals(archived))
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    return q.watch().map((rows) => rows.map(_course).toList());
  }

  Stream<Course?> watchCourse(String id) =>
      (_db.select(_db.courses)..where((c) => c.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _course(r));

  Future<Course?> getCourse(String id) async {
    final r = await (_db.select(
      _db.courses,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return r == null ? null : _course(r);
  }

  Future<List<Course>> allCourses() async =>
      (await _db.select(_db.courses).get()).map(_course).toList();

  Future<void> saveCourse(Course course) =>
      _writer.upsert('courses', courseToWire(course));

  /// Deletes the course with its students, assignments and evaluations.
  ///
  /// Children go first and explicitly — not by the local foreign-key
  /// cascade — so every removed row reaches the server as its own tombstone
  /// and other devices remove it too.
  Future<void> deleteCourse(String id) async {
    final assignments = await (_db.select(
      _db.assignments,
    )..where((a) => a.courseId.equals(id))).get();
    for (final a in assignments) {
      final evaluations = await (_db.select(
        _db.evaluations,
      )..where((e) => e.assignmentId.equals(a.id))).get();
      for (final e in evaluations) {
        await _writer.delete('evaluations', e.id);
      }
      await _writer.delete('assignments', a.id);
    }
    final students = await (_db.select(
      _db.students,
    )..where((s) => s.courseId.equals(id))).get();
    for (final s in students) {
      await deleteStudent(s.id);
    }
    await _writer.delete('courses', id);
  }

  /// Active students, sorted by last then first name.
  Stream<List<Student>> watchStudents(
    String courseId, {
    bool archived = false,
  }) {
    final q = _db.select(_db.students)
      ..where((s) => s.courseId.equals(courseId) & s.archived.equals(archived))
      ..orderBy([
        (s) => OrderingTerm.asc(s.lastName.lower()),
        (s) => OrderingTerm.asc(s.firstName.lower()),
      ]);
    return q.watch().map((rows) => rows.map(_student).toList());
  }

  Future<List<Student>> students(
    String courseId, {
    bool includeArchived = false,
  }) async {
    final q = _db.select(_db.students)
      ..where(
        (s) => includeArchived
            ? s.courseId.equals(courseId)
            : s.courseId.equals(courseId) & s.archived.equals(false),
      );
    final list = (await q.get()).map(_student).toList()..sort(compareStudents);
    return list;
  }

  Future<List<Student>> allStudents() async =>
      (await _db.select(_db.students).get()).map(_student).toList();

  Stream<Student?> watchStudent(String id) =>
      (_db.select(_db.students)..where((s) => s.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _student(r));

  Future<void> saveStudent(Student student) =>
      _writer.upsert('students', studentToWire(student));

  Future<void> saveStudents(Iterable<Student> students) async {
    for (final s in students) {
      await saveStudent(s);
    }
  }

  /// Deletes the student and their evaluations (each as its own tombstone).
  Future<void> deleteStudent(String id) async {
    final evaluations = await (_db.select(
      _db.evaluations,
    )..where((e) => e.studentId.equals(id))).get();
    for (final e in evaluations) {
      await _writer.delete('evaluations', e.id);
    }
    await _writer.delete('students', id);
  }

  /// Active student count per course id.
  Stream<Map<String, int>> watchStudentCounts() {
    final count = _db.students.id.count();
    final q = _db.selectOnly(_db.students)
      ..addColumns([_db.students.courseId, count])
      ..where(_db.students.archived.equals(false))
      ..groupBy([_db.students.courseId]);
    return q.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.students.courseId)!: r.read(count) ?? 0,
      },
    );
  }
}
