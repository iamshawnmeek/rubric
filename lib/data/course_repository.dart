import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/classroom.dart';

class CourseRepository {
  new(this._db);

  final AppDatabase _db;

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

  static StudentsCompanion _studentRow(Student s) => StudentsCompanion.insert(
    id: s.id,
    courseId: s.courseId,
    firstName: s.firstName,
    lastName: Value(s.lastName),
    studentNumber: Value(s.studentNumber),
    email: Value(s.email),
    notes: Value(s.notes),
    archived: Value(s.archived),
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

  Future<void> saveCourse(Course course) => _db
      .into(_db.courses)
      .insertOnConflictUpdate(
        CoursesCompanion.insert(
          id: course.id,
          name: course.name,
          section: Value(course.section),
          term: Value(course.term),
          archived: Value(course.archived),
          createdAt: course.createdAt,
        ),
      );

  /// Deletes the course and — by cascade — its students, assignments and
  /// evaluations.
  Future<void> deleteCourse(String id) =>
      (_db.delete(_db.courses)..where((c) => c.id.equals(id))).go();

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
      _db.into(_db.students).insertOnConflictUpdate(_studentRow(student));

  Future<void> saveStudents(Iterable<Student> students) => _db.batch(
    (b) => b.insertAllOnConflictUpdate(_db.students, students.map(_studentRow)),
  );

  Future<void> deleteStudent(String id) =>
      (_db.delete(_db.students)..where((s) => s.id.equals(id))).go();

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
