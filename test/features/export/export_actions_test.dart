import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/export/export_actions.dart';
import 'package:rubric/features/export/export_platform.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fixtures.dart';
import 'export_test_helpers.dart';

final _course = Course(id: 'c1', name: 'English 10', createdAt: t0);
final _assignment = Assignment(
  id: 'a1',
  courseId: 'c1',
  title: 'Essay',
  rubric: essayRubric(mode: GradingMode.detailed),
  createdAt: t0,
);
const _ada = Student(
  id: 's1',
  courseId: 'c1',
  firstName: 'Ada',
  lastName: 'Lovelace',
);

Future<void> _seed(AppDatabase db) async {
  final courses = CourseRepository(db);
  await courses.saveCourse(_course);
  await courses.saveStudents([
    _ada,
    const Student(id: 's2', courseId: 'c1', firstName: 'Bo', lastName: 'Diaz'),
    // Withdrawn after being graded: still exported.
    const Student(
      id: 's3',
      courseId: 'c1',
      firstName: 'Cy',
      lastName: 'Gone',
      archived: true,
    ),
    // Withdrawn before any work: left out.
    const Student(
      id: 's4',
      courseId: 'c1',
      firstName: 'Di',
      lastName: 'Never',
      archived: true,
    ),
  ]);
  await AssignmentRepository(db).save(_assignment);
  await AssignmentRepository(db).saveEvaluations([
    eval(const {
      'o1': LevelScore('L4'),
      'o2': LevelScore('L4'),
      'o3': LevelScore('L4'),
    }, status: EvaluationStatus.complete),
    eval(const {'o1': LevelScore('L2')}, student: 's3'),
  ]);
}

/// A page with one button per export entry point.
class _Exports extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    Widget button(String label, Future<void> Function(BuildContext) run) =>
        Builder(
          builder: (context) =>
              TextButton(onPressed: () => run(context), child: Text(label)),
        );
    return Scaffold(
      body: ListView(
        children: [
          button('rubric', (c) => exportRubricPdf(c, _assignment.rubric)),
          button(
            'student',
            (c) => exportStudentReportPdf(
              c,
              assignment: _assignment,
              student: _ada,
            ),
          ),
          button(
            'reports',
            (c) => exportAssignmentReportsPdf(c, assignment: _assignment),
          ),
          button('csv', (c) => exportAssignmentCsv(c, assignment: _assignment)),
          button('gradebook', (c) => exportGradebookCsv(c, course: _course)),
        ],
      ),
    );
  }
}

void main() {
  late FakeExportPlatform platform;
  setUp(() => platform = FakeExportPlatform());

  Future<void> pump(WidgetTester tester) => pumpPage(
    tester,
    const _Exports(),
    seed: _seed,
    overrides: [exportPlatformProvider.overrideWithValue(platform)],
  );

  Future<void> run(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Picks [option] in the PDF sheet and waits for the document to land.
  /// PDF layout yields to the event loop on 1ms timers, so the fake clock
  /// has to be advanced rather than settled.
  Future<void> choose(WidgetTester tester, String option) async {
    final before = platform.sharedPdfs.length + platform.printed.length;
    await tester.tap(find.text(option));
    for (var i = 0; i < 500; i++) {
      await tester.pump(const Duration(milliseconds: 5));
      if (platform.sharedPdfs.length + platform.printed.length > before) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('assignment CSV lists the roster with grades', (tester) async {
    await pump(tester);
    await run(tester, 'csv');

    final file = platform.shared.single;
    expect(file.mimeType, 'text/csv');
    expect(
      file.filename,
      matches(RegExp(r'^essay-scores-\d{4}-\d{2}-\d{2}\.csv$')),
    );
    expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM');
    final lines = utf8.decode(file.bytes.skip(3).toList()).split('\r\n');
    expect(lines, hasLength(4), reason: 'header + Diaz, Gone, Lovelace');
    expect(lines[1], startsWith('Diaz,Bo,,Not started'));
    expect(lines[2], startsWith('Gone,Cy,,In progress,Developing'));
    expect(lines[3], startsWith('Lovelace,Ada,,Complete,Exemplary'));
    expect(lines[3], contains(',100,A,100,'));
  });

  testWidgets('gradebook CSV has one column per assignment', (tester) async {
    await pump(tester);
    await run(tester, 'gradebook');
    final text = utf8.decode(platform.shared.single.bytes.skip(3).toList());
    expect(
      text.split('\r\n').first,
      'Last name,First name,Student #,Essay,Average %',
    );
    expect(text, contains('Lovelace,Ada,,100,100'));
    expect(
      platform.shared.single.filename,
      startsWith('english-10-gradebook-'),
    );
  });

  testWidgets('rubric PDF offers print and share', (tester) async {
    await pump(tester);
    await run(tester, 'rubric');
    expect(find.text('Print'), findsOneWidget);
    expect(find.text('Share PDF'), findsOneWidget);

    await choose(tester, 'Share PDF');
    final pdf = platform.sharedPdfs.single;
    expect(isPdf(pdf.bytes), isTrue);
    expect(pdf.filename, matches(RegExp(r'^essay-\d{4}-\d{2}-\d{2}\.pdf$')));

    await run(tester, 'rubric');
    await choose(tester, 'Print');
    expect(isPdf(platform.printed.single.bytes), isTrue);
    expect(platform.printed.single.name, 'Essay');
  });

  testWidgets('dismissing the sheet exports nothing', (tester) async {
    await pump(tester);
    await run(tester, 'rubric');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Share PDF'), findsNothing);
    expect(platform.sharedPdfs, isEmpty);
    expect(platform.printed, isEmpty);
  });

  testWidgets('student and class reports produce PDFs', (tester) async {
    await pump(tester);
    await run(tester, 'student');
    await choose(tester, 'Share PDF');
    expect(isPdf(platform.sharedPdfs.last.bytes), isTrue);
    expect(
      platform.sharedPdfs.last.filename,
      startsWith('essay-ada-lovelace-'),
    );

    await run(tester, 'reports');
    await choose(tester, 'Share PDF');
    final reports = platform.sharedPdfs.last.bytes;
    expect(isPdf(reports), isTrue);
    // Three students on the roster (Diaz, Gone, Lovelace): three pages.
    expect(
      RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(reports)),
      hasLength(3),
    );
  });

  testWidgets('a failure shows a message instead of crashing', (tester) async {
    platform = _FailingPlatform();
    await pump(tester);
    await run(tester, 'csv');
    expect(find.text('Export failed. Please try again.'), findsOneWidget);
  });
}

class _FailingPlatform extends FakeExportPlatform {
  @override
  Future<bool> shareFile({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String? subject,
    Rect? origin,
  }) => Future.error(StateError('no share sheet'));
}
