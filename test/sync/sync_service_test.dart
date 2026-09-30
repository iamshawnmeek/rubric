import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/sync/sync_service.dart';

import '../helpers/db.dart';
import '../helpers/fake_zonai.dart';

const email = 'teacher@school.test';

/// One phone or tablet: its own database and sync, sharing one server.
final class Device {
  new _(this.db, this.sync, this.session)
    : courses = CourseRepository(db, sync);

  static Future<Device> open(FakeZonai server, {MemorySession? session}) async {
    final db = testDatabase();
    final saved = session ?? MemorySession();
    final sync = await SyncService.open(
      db: db,
      remote: server,
      auth: FakeAuth(server),
      session: saved,
      pullOverlap: Duration.zero,
    );
    return Device._(db, sync, saved);
  }

  final AppDatabase db;
  final SyncService sync;
  final MemorySession session;
  final CourseRepository courses;

  Future<void> signIn() => sync.signIn(email: email, password: 'password1');

  /// Runs passes until the one this call started has finished: a write
  /// already kicks off a pass, and a sync requested while one runs may join
  /// it rather than start another.
  Future<void> settle() async {
    await pumpEventQueue();
    await sync.syncNow();
    await sync.syncNow();
  }

  Future<List<String>> courseNames() async =>
      [for (final c in await courses.allCourses()) c.name]..sort();

  Future<List<String>> studentNames() async =>
      [for (final s in await courses.allStudents()) s.firstName]..sort();

  Future<void> close() async {
    await sync.dispose();
    await db.close();
  }
}

void main() {
  late FakeZonai server;
  final devices = <Device>[];

  Future<Device> device({MemorySession? session}) async {
    final d = await Device.open(server, session: session);
    devices.add(d);
    return d;
  }

  setUp(() => server = FakeZonai());
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
  });

  Map<String, Map<String, Object?>> rows(String table) =>
      server.tables[table] ?? {};

  test('signed out, writes stay on the device', () async {
    final a = await device();
    await a.courses.saveCourse(Course.create(name: 'Biology'));
    await a.settle();

    expect(await a.courseNames(), ['Biology']);
    expect(server.calls, isEmpty);
    expect(a.sync.state.signedIn, isFalse);
  });

  test(
    'the first sign-in keeps what the teacher made and uploads it',
    () async {
      final a = await device();
      final course = Course.create(name: 'Biology');
      await a.courses.saveCourse(course);
      await a.courses.saveStudent(
        Student.create(courseId: course.id, firstName: 'Ada'),
      );

      await a.signIn();
      await a.settle();

      expect(await a.courseNames(), ['Biology']);
      expect(rows('courses')[course.id], containsPair('owner_id', 'u1'));
      expect(rows('students').values.single, containsPair('first_name', 'Ada'));
      expect(a.sync.state.status.pending, 0);
    },
  );

  test('two devices on one account converge, both ways', () async {
    final phone = await device();
    final tablet = await device();
    await phone.signIn();
    final course = Course.create(name: 'Biology');
    await phone.courses.saveCourse(course);
    await phone.courses.saveStudents([
      Student.create(courseId: course.id, firstName: 'Ada'),
      Student.create(courseId: course.id, firstName: 'Grace'),
    ]);
    await phone.settle();

    await tablet.signIn();
    await tablet.settle();
    expect(await tablet.courseNames(), ['Biology']);
    expect(await tablet.studentNames(), ['Ada', 'Grace']);

    await tablet.courses.saveCourse(
      (await tablet.courses.getCourse(course.id))!.copyWith(name: 'Biology 2'),
    );
    await tablet.settle();
    await phone.settle();
    expect(await phone.courseNames(), ['Biology 2']);
    expect(rows('courses')[course.id]!['rev'], 2);
  });

  test('deleting a class on one device removes it and its students on the '
      'other', () async {
    final phone = await device();
    final tablet = await device();
    await phone.signIn();
    await tablet.signIn();
    final course = Course.create(name: 'Biology');
    await phone.courses.saveCourse(course);
    await phone.courses.saveStudent(
      Student.create(courseId: course.id, firstName: 'Ada'),
    );
    await phone.settle();
    await tablet.settle();
    expect(await tablet.studentNames(), ['Ada']);

    await phone.courses.deleteCourse(course.id);
    await phone.settle();

    expect(rows('courses')[course.id]!['deleted_at'], isNotNull);
    expect(rows('students').values.single['deleted_at'], isNotNull);
    await tablet.settle();
    expect(await tablet.courseNames(), isEmpty);
    expect(await tablet.studentNames(), isEmpty);
  });

  group('bulk', () {
    test('queues exactly what a direct database change did', () async {
      final phone = await device();
      await phone.signIn();
      final kept = Course.create(name: 'Kept');
      final doomed = Course.create(name: 'Doomed');
      await phone.courses.saveCourse(kept);
      await phone.courses.saveCourse(doomed);
      final ada = Student.create(courseId: doomed.id, firstName: 'Ada');
      await phone.courses.saveStudent(ada);
      await phone.settle();
      server.calls.clear();

      final added = Course.create(name: 'Added');
      // A replace-style restore: rows removed and added behind sync's back.
      await phone.sync.bulk(() async {
        final db = phone.db;
        await (db.delete(db.students)..where((t) => t.id.equals(ada.id))).go();
        await (db.delete(
          db.courses,
        )..where((t) => t.id.equals(doomed.id))).go();
        await db
            .into(db.courses)
            .insert(
              CoursesCompanion.insert(
                id: added.id,
                name: added.name,
                createdAt: added.createdAt,
              ),
            );
      });
      await phone.settle();

      expect(await phone.courseNames(), ['Added', 'Kept']);
      expect(await phone.studentNames(), isEmpty);
      expect(rows('courses')[doomed.id]!['deleted_at'], isNotNull);
      expect(rows('students')[ada.id]!['deleted_at'], isNotNull);
      expect(rows('courses')[added.id], containsPair('name', 'Added'));
      // Positive control above; and the untouched row was not re-sent.
      expect(
        server.calls,
        isNot(contains(startsWith('update courses/${kept.id}'))),
      );
      expect(server.calls, contains('create courses/${added.id}'));
    });

    test('signed out, it only runs the change', () async {
      final phone = await device();
      final result = await phone.sync.bulk(() async => 42);
      expect(result, 42);
      expect(server.calls, isEmpty);
    });
  });

  test(
    'sign-out removes the account from the device; sign-in brings it back',
    () async {
      final session = MemorySession();
      final phone = await device(session: session);
      await phone.signIn();
      await phone.courses.saveCourse(Course.create(name: 'Biology'));
      await phone.settle();

      await phone.sync.signOut();
      expect(await phone.courseNames(), isEmpty);
      expect(session.saved, isNull);
      expect(rows('courses'), hasLength(1));

      await phone.signIn();
      await phone.settle();
      expect(await phone.courseNames(), ['Biology']);
    },
  );

  test('a saved session is restored at launch', () async {
    final session = MemorySession();
    final first = await device(session: session);
    await first.signIn();
    expect(session.saved?.id, 'u1');

    final relaunched = await device(session: session);
    expect(relaunched.sync.state.account?.email, email);
  });

  test(
    'a failed sign-in leaves the device signed out and its data alone',
    () async {
      final phone = await device();
      await phone.courses.saveCourse(Course.create(name: 'Biology'));
      await expectLater(
        phone.sync.signIn(email: 'stranger@school.test', password: 'password1'),
        throwsA(anything),
      );
      expect(phone.sync.state.signedIn, isFalse);
      expect(await phone.courseNames(), ['Biology']);
      expect(server.calls, isEmpty);
    },
  );
}
