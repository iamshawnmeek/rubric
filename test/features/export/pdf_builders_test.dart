import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/export/pdf_builders.dart';

import '../../helpers/export_fakes.dart';
import '../../helpers/fixtures.dart';

StudentReport _report(
  GradingMode mode, {
  Evaluation? evaluation,
  String studentId = 's1',
}) => StudentReport(
  assignment: Assignment(
    id: 'a1',
    courseId: 'c1',
    title: 'Persuasive essay',
    rubric: essayRubric(mode: mode),
    createdAt: t0,
  ),
  student: Student(
    id: studentId,
    courseId: 'c1',
    firstName: 'Ada',
    lastName: 'Lovelace',
    studentNumber: '001',
  ),
  evaluation: evaluation,
  date: t0,
  courseName: 'English 10 — Period 3',
  teacherName: 'Ms. Walker',
);

/// Pages in the document. Page dictionaries are not compressed, so the
/// marker is visible in the raw bytes.
int _pageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length;

void main() {
  final fonts = testFonts();
  setUpAll(initializeDateFormatting);

  test('the bundled Avenir faces cover the punctuation documents use', () {
    for (final face in ['Light', 'Heavy', 'Black']) {
      final font = PdfTtfFont(
        PdfDocument(),
        ByteData.sublistView(fontBytes(face)),
      );
      for (final char in '—·…’%#'.runes) {
        expect(
          font.isRuneSupported(char),
          isTrue,
          reason: '$face lacks ${String.fromCharCode(char)}',
        );
      }
    }
  });

  group('buildRubricPdf', () {
    for (final mode in GradingMode.values) {
      test('${mode.name} rubric produces a valid PDF', () async {
        final bytes = await buildRubricPdf(
          l10n: l10nEn,
          rubric: essayRubric(mode: mode).copyWith(
            description: 'Argue a position, with sources.',
            subject: 'English',
          ),
          fonts: fonts,
        );
        expect(isPdf(bytes), isTrue);
        expect(_pageCount(bytes), 1);
      });
    }

    test('detailed rubrics are landscape, simple ones portrait', () {
      expect(
        pageFormatFor(essayRubric(mode: GradingMode.detailed)).width,
        greaterThan(pageFormatFor(essayRubric()).width),
      );
      final a4 = pageFormatFor(essayRubric(), PdfPageFormat.a4);
      expect(a4.height, PdfPageFormat.a4.height);
    });

    test('a long rubric flows onto more pages', () async {
      final long = essayRubric().copyWith(
        groups: [
          RubricGroup(
            id: 'g',
            title: 'Everything',
            weight: 100,
            objectives: [
              for (var i = 0; i < 80; i++)
                Objective(id: 'o$i', title: 'Objective $i'),
            ],
          ),
        ],
      );
      final bytes = await buildRubricPdf(
        l10n: l10nEn,
        rubric: long,
        fonts: fonts,
      );
      expect(_pageCount(bytes), greaterThan(1));
    });
  });

  group('buildStudentReportPdf', () {
    test('simple report with penalty and comments', () async {
      final bytes = await buildStudentReportPdf(
        l10n: l10nEn,
        report: _report(
          GradingMode.simple,
          evaluation:
              eval(const {
                'o1': PercentScore(80),
                'o3': PercentScore(90),
              }, penalty: 10).copyWith(
                comment: 'Strong thesis.',
                late: true,
                objectiveComments: {'o1': 'Watch commas.'},
              ),
        ),
        fonts: fonts,
      );
      expect(isPdf(bytes), isTrue);
    });

    test('detailed report with an achieved level and an override', () async {
      final bytes = await buildStudentReportPdf(
        l10n: l10nEn,
        report: _report(
          GradingMode.detailed,
          evaluation: eval(const {
            'o1': LevelScore('L4'),
            'o2': LevelScore('L2'),
          }, override: 95),
        ),
        fonts: fonts,
      );
      expect(isPdf(bytes), isTrue);
    });

    test('ungraded and excused students still get a report', () async {
      for (final evaluation in [
        null,
        eval(const {}, status: EvaluationStatus.excused),
        eval(const {}, status: EvaluationStatus.missing),
      ]) {
        final bytes = await buildStudentReportPdf(
          l10n: l10nEn,
          report: _report(GradingMode.simple, evaluation: evaluation),
          fonts: fonts,
        );
        expect(isPdf(bytes), isTrue);
      }
    });
  });

  group('buildAssignmentReportsPdf', () {
    test('one student per page', () async {
      final bytes = await buildAssignmentReportsPdf(
        l10n: l10nEn,
        reports: [
          for (final id in ['s1', 's2', 's3'])
            _report(
              GradingMode.simple,
              studentId: id,
              evaluation: eval(const {'o1': PercentScore(70)}, student: id),
            ),
        ],
        fonts: fonts,
      );
      expect(isPdf(bytes), isTrue);
      expect(_pageCount(bytes), 3);
    });

    test('an empty class still produces a document', () async {
      final bytes = await buildAssignmentReportsPdf(
        l10n: l10nEn,
        reports: const [],
        fonts: fonts,
      );
      expect(isPdf(bytes), isTrue);
      expect(_pageCount(bytes), 1);
    });
  });
}
