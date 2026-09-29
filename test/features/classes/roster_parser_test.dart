import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/classes/roster_parser.dart';

Student _student(String first, String last, {String number = ''}) => Student(
  id: '$first$last',
  courseId: 'c1',
  firstName: first,
  lastName: last,
  studentNumber: number,
);

void main() {
  group('parseCsv', () {
    test('strips a UTF-8 BOM so the first header still matches', () {
      final table = parseCsv('﻿First Name,Last Name\nAda,Lovelace\n');
      expect(table.rows.first, ['First Name', 'Last Name']);
      expect(fieldForHeader(table.rows.first.first), RosterField.firstName);
    });

    test('honours quoted fields with commas, quotes and newlines', () {
      final table = parseCsv(
        'name,notes\n"Lovelace, Ada","said ""hi"""\n"Hopper, Grace","two\nlines"\n',
      );
      expect(table.rows, [
        ['name', 'notes'],
        ['Lovelace, Ada', 'said "hi"'],
        ['Hopper, Grace', 'two\nlines'],
      ]);
    });

    test('drops blank rows, trims cells and pads ragged rows', () {
      final table = parseCsv('a, b ,c\r\n\r\n,,\r\n x ,y\r\n');
      expect(table.rows, [
        ['a', 'b', 'c'],
        ['x', 'y', ''],
      ]);
      expect(table.columnCount, 3);
    });

    test('detects semicolon- and tab-delimited files', () {
      expect(parseCsv('first;last\nAda;Lovelace').rows[1], ['Ada', 'Lovelace']);
      expect(parseCsv('first\tlast\nAda\tLovelace').rows[1], [
        'Ada',
        'Lovelace',
      ]);
    });

    test('empty or whitespace input is an empty table', () {
      expect(parseCsv('').isEmpty, isTrue);
      expect(parseCsv('﻿  \n ').isEmpty, isTrue);
    });
  });

  group('header detection', () {
    test('recognises common spellings of each field', () {
      expect(
        detectColumns([
          'First Name',
          'SURNAME',
          'Student ID',
          'E-mail',
          'Period',
        ]),
        [
          RosterField.firstName,
          RosterField.lastName,
          RosterField.studentNumber,
          RosterField.email,
          RosterField.ignore,
        ],
      );
      expect(detectColumns(['Student Name', '#']), [
        RosterField.fullName,
        RosterField.studentNumber,
      ]);
    });

    test('a field is claimed only by its leftmost column', () {
      expect(detectColumns(['Email', 'School Email']), [
        RosterField.email,
        RosterField.ignore,
      ]);
    });

    test('looksLikeHeader tells headers from data', () {
      expect(looksLikeHeader(['First', 'Last']), isTrue);
      expect(looksLikeHeader(['Ada', 'Lovelace']), isFalse);
    });

    test('guessColumns maps headerless data by its shape', () {
      expect(
        guessColumns([
          ['1001', 'Ada Lovelace', 'ada@school.org'],
          ['1002', 'Grace Hopper', 'grace@school.org'],
        ]),
        [RosterField.studentNumber, RosterField.fullName, RosterField.email],
      );
    });
  });

  group('splitName', () {
    test('"Last, First"', () {
      expect(splitName('Lovelace, Ada'), (first: 'Ada', last: 'Lovelace'));
      expect(splitName('de la Cruz,  Juan Pablo'), (
        first: 'Juan Pablo',
        last: 'de la Cruz',
      ));
    });

    test('"First Last" keeps middle names with the first name', () {
      expect(splitName('Ada Lovelace'), (first: 'Ada', last: 'Lovelace'));
      expect(splitName('  Mary   Ann Smith '), (
        first: 'Mary Ann',
        last: 'Smith',
      ));
    });

    test('a single word is a first name', () {
      expect(splitName('Cher'), (first: 'Cher', last: ''));
      expect(splitName('Cher,'), (first: 'Cher', last: ''));
    });
  });

  group('parseNameLines', () {
    test('splits lines, mixes formats, drops blanks and list markers', () {
      expect(
        parseNameLines(
          'Lovelace, Ada\r\n\n  Grace Hopper\n1. Alan Turing\n- "Katherine Johnson"\n• Cher\n',
        ),
        [
          (first: 'Ada', last: 'Lovelace'),
          (first: 'Grace', last: 'Hopper'),
          (first: 'Alan', last: 'Turing'),
          (first: 'Katherine', last: 'Johnson'),
          (first: 'Cher', last: ''),
        ],
      );
    });
  });

  group('buildCandidates', () {
    test('uses first/last columns, else splits the full name', () {
      final c = buildCandidates(
        [
          ['Ada', 'Lovelace', 'Ignored Name', '7', 'ada@x.org'],
        ],
        [
          RosterField.firstName,
          RosterField.lastName,
          RosterField.fullName,
          RosterField.studentNumber,
          RosterField.email,
        ],
        existing: const [],
      ).single;
      expect(c.displayName, 'Ada Lovelace');
      expect(c.studentNumber, '7');
      expect(c.email, 'ada@x.org');
      expect(c.issues, isEmpty);

      final split = buildCandidates(
        [
          ['Hopper, Grace'],
        ],
        [RosterField.fullName],
        existing: const [],
      ).single;
      expect((split.firstName, split.lastName), ('Grace', 'Hopper'));
    });

    test('a blank name cannot be imported', () {
      final c = buildCandidates(
        [
          ['', '', '42'],
        ],
        [
          RosterField.firstName,
          RosterField.lastName,
          RosterField.studentNumber,
        ],
        existing: const [],
      ).single;
      expect(c.issues, {RosterIssue.missingName});
      expect(c.importable, isFalse);
      expect(c.selectedByDefault, isFalse);
    });

    test('flags students already on the roster by number, then by name', () {
      final existing = [
        _student('Ada', 'Lovelace', number: '100'),
        _student('Grace', 'Hopper'),
      ];
      final mapping = [
        RosterField.firstName,
        RosterField.lastName,
        RosterField.studentNumber,
      ];
      final rows = [
        ['Augusta', 'King', '100'], // same number, different name
        ['grace', 'HOPPER', ''], // same name, case-insensitive
        ['Ada', 'Lovelace', '200'], // same name, different number: new student
        ['Alan', 'Turing', ''],
      ];
      final issues = buildCandidates(
        rows,
        mapping,
        existing: existing,
      ).map((c) => c.issues).toList();
      expect(issues, [
        {RosterIssue.alreadyOnRoster},
        {RosterIssue.alreadyOnRoster},
        <RosterIssue>{},
        <RosterIssue>{},
      ]);
    });

    test('flags repeats within the file but keeps the first occurrence', () {
      final candidates = buildCandidates(
        [
          ['Alan Turing', '1'],
          ['Alan Turing', '1'],
          ['Grace Hopper', ''],
          ['Grace  Hopper', ''],
        ],
        [RosterField.fullName, RosterField.studentNumber],
        existing: const [],
      );
      expect(candidates.map((c) => c.issues.isEmpty), [
        true,
        false,
        true,
        false,
      ]);
      expect(candidates[1].issues, {RosterIssue.duplicateInFile});
    });

    test('toStudent carries every mapped field into the course', () {
      final s = buildCandidates(
        [
          ['Ada', 'Lovelace', '7', 'ada@x.org'],
        ],
        [
          RosterField.firstName,
          RosterField.lastName,
          RosterField.studentNumber,
          RosterField.email,
        ],
        existing: const [],
      ).single.toStudent('c9');
      expect(s.courseId, 'c9');
      expect(s.sortName, 'Lovelace, Ada');
      expect(s.studentNumber, '7');
      expect(s.email, 'ada@x.org');
    });
  });

  test('candidatesFromNames flags pasted names already in the class', () {
    final c = candidatesFromNames(
      parseNameLines('Grace Hopper\nAlan Turing\nalan turing'),
      existing: [_student('Grace', 'Hopper')],
    );
    expect(c.map((c) => c.issues), [
      {RosterIssue.alreadyOnRoster},
      <RosterIssue>{},
      {RosterIssue.duplicateInFile},
    ]);
  });
}
