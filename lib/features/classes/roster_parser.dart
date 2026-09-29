import 'package:csv/csv.dart';
import 'package:rubric/domain/classroom.dart';

/// Pure parsing and validation for roster imports: CSV text in, a list of
/// reviewable [RosterCandidate]s out. No Flutter imports; every rule here is
/// unit-tested in `test/features/classes/roster_parser_test.dart`.

/// What a CSV column holds.
enum RosterField { ignore, firstName, lastName, fullName, studentNumber, email }

/// Why a row should not be imported as-is.
enum RosterIssue {
  /// Neither a first nor a last name could be found. Cannot be imported.
  missingName,

  /// Matches a student already in the class (by number, else by name).
  alreadyOnRoster,

  /// Matches an earlier row of the same import.
  duplicateInFile,
}

/// A CSV decoded into trimmed, rectangular string cells.
class RosterTable {
  const new(this.rows);

  /// Every non-blank row, padded to [columnCount].
  final List<List<String>> rows;

  int get columnCount => rows.isEmpty ? 0 : rows.first.length;

  bool get isEmpty => rows.isEmpty;
}

/// Decodes [text] as CSV. Strips a UTF-8 byte-order mark, auto-detects the
/// delimiter (comma, semicolon, tab), honours quoting, trims every cell and
/// drops rows that are entirely blank.
RosterTable parseCsv(String text) {
  var input = text;
  if (input.startsWith('﻿')) input = input.substring(1);
  if (input.trim().isEmpty) return const RosterTable([]);

  final decoded = Csv().decode(input);
  final rows = [
    for (final row in decoded) [for (final cell in row) '${cell ?? ''}'.trim()],
  ].where((row) => row.any((cell) => cell.isNotEmpty)).toList();

  final width = rows.fold(0, (w, r) => r.length > w ? r.length : w);
  return RosterTable([
    for (final row in rows)
      [...row, for (var i = row.length; i < width; i++) ''],
  ]);
}

String _normalizeHeader(String header) =>
    header.toLowerCase().replaceAll(RegExp('[^a-z0-9#]'), '');

const _headerAliases = <RosterField, Set<String>>{
  RosterField.firstName: {
    'first',
    'firstname',
    'fname',
    'given',
    'givenname',
    'forename',
    'studentfirstname',
    'legalfirstname',
    'preferredname',
    'preferredfirstname',
  },
  RosterField.lastName: {
    'last',
    'lastname',
    'lname',
    'surname',
    'family',
    'familyname',
    'studentlastname',
    'legallastname',
  },
  RosterField.fullName: {
    'name',
    'fullname',
    'student',
    'studentname',
    'displayname',
    'lastfirst',
    'firstlast',
  },
  RosterField.studentNumber: {
    'id',
    '#',
    'no',
    'number',
    'studentid',
    'studentnumber',
    'studentno',
    'student#',
    'sisid',
    'idnumber',
    'localid',
    'stateid',
    'userid',
  },
  RosterField.email: {
    'email',
    'emailaddress',
    'mail',
    'studentemail',
    'schoolemail',
  },
};

/// The field a header most likely names, or [RosterField.ignore].
RosterField fieldForHeader(String header) {
  final key = _normalizeHeader(header);
  if (key.isEmpty) return RosterField.ignore;
  for (final MapEntry(key: field, value: aliases) in _headerAliases.entries) {
    if (aliases.contains(key)) return field;
  }
  return RosterField.ignore;
}

/// Maps each column of [header] to a field. Each field is claimed by at most
/// one column (the leftmost); unrecognised columns are ignored.
List<RosterField> detectColumns(List<String> header) {
  final claimed = <RosterField>{};
  return [
    for (final cell in header)
      switch (fieldForHeader(cell)) {
        RosterField.ignore => RosterField.ignore,
        final field when claimed.add(field) => field,
        _ => RosterField.ignore,
      },
  ];
}

/// Whether [row] reads like a header row rather than a student.
bool looksLikeHeader(List<String> row) =>
    row.any((cell) => fieldForHeader(cell) != RosterField.ignore);

/// When there is no header, guesses a mapping from the data: an `@` column is
/// email, an all-digit column is the student number, and the first remaining
/// text column is a full name.
List<RosterField> guessColumns(List<List<String>> rows) {
  if (rows.isEmpty) return const [];
  final width = rows.first.length;
  final fields = List.filled(width, RosterField.ignore);
  bool all(int col, bool Function(String) test) {
    final values = rows.map((r) => r[col]).where((v) => v.isNotEmpty);
    return values.isNotEmpty && values.every(test);
  }

  for (var c = 0; c < width; c++) {
    if (!fields.contains(RosterField.email) && all(c, (v) => v.contains('@'))) {
      fields[c] = RosterField.email;
    } else if (!fields.contains(RosterField.studentNumber) &&
        all(c, (v) => RegExp(r'^[A-Za-z]?\d[\d-]*$').hasMatch(v))) {
      fields[c] = RosterField.studentNumber;
    }
  }
  final nameCol = fields.indexWhere((f) => f == RosterField.ignore);
  if (nameCol != -1) fields[nameCol] = RosterField.fullName;
  return fields;
}

/// A first/last pair.
typedef PersonName = ({String first, String last});

/// Splits one name. "Lovelace, Ada" is last-comma-first; otherwise the final
/// word is the last name ("Mary Ann Smith" → Mary Ann / Smith) and a single
/// word is a first name only.
PersonName splitName(String raw) {
  final name = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final comma = name.indexOf(',');
  if (comma != -1) {
    final last = name.substring(0, comma).trim();
    final first = name.substring(comma + 1).replaceAll(',', ' ').trim();
    return first.isEmpty ? (first: last, last: '') : (first: first, last: last);
  }
  final space = name.lastIndexOf(' ');
  if (space == -1) return (first: name, last: '');
  return (first: name.substring(0, space), last: name.substring(space + 1));
}

/// Splits pasted text into names, one per line. Blank lines, leading list
/// markers ("1.", "-", "•") and surrounding quotes are dropped.
List<PersonName> parseNameLines(String text) {
  final marker = RegExp(r'^(\d+[.)]|[-*•·])\s+');
  return [
    for (final line in text.split(RegExp(r'\r\n|\r|\n')))
      if (line
              .replaceAll('\t', ' ')
              .trim()
              .replaceFirst(marker, '')
              .replaceAll('"', '')
              .trim()
          case final cleaned when cleaned.isNotEmpty)
        splitName(cleaned),
  ];
}

/// One row, ready for review.
class RosterCandidate {
  const new({
    required this.row,
    required this.firstName,
    required this.lastName,
    this.studentNumber = '',
    this.email = '',
    this.issues = const {},
  });

  /// Index into the source rows (or pasted lines).
  final int row;
  final String firstName;
  final String lastName;
  final String studentNumber;
  final String email;
  final Set<RosterIssue> issues;

  bool get importable => !issues.contains(RosterIssue.missingName);

  /// Clean rows are pre-selected; anything flagged waits for the teacher.
  bool get selectedByDefault => issues.isEmpty;

  String get displayName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  Student toStudent(String courseId) => Student.create(
    courseId: courseId,
    firstName: firstName,
    lastName: lastName,
    studentNumber: studentNumber,
    email: email,
  );
}

String _nameKey(String first, String last) => '${first.trim()} ${last.trim()}'
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

String _numberKey(String number) => number.trim().toLowerCase();

/// Decides whether a new person matches someone already seen. A shared
/// student number is a match; otherwise the same name is — unless both carry
/// numbers and they differ (two different students who share a name).
class RosterMatcher {
  new(Iterable<Student> existing) {
    for (final s in existing) {
      _add(s.firstName, s.lastName, s.studentNumber);
    }
  }

  final _numbers = <String>{};
  final _names = <String, Set<String>>{};

  void _add(String first, String last, String number) {
    final n = _numberKey(number);
    if (n.isNotEmpty) _numbers.add(n);
    _names.putIfAbsent(_nameKey(first, last), () => {}).add(n);
  }

  bool matches(String first, String last, String number) {
    final n = _numberKey(number);
    if (n.isNotEmpty && _numbers.contains(n)) return true;
    final numbersForName = _names[_nameKey(first, last)];
    if (numbersForName == null) return false;
    if (n.isEmpty) return true;
    return numbersForName.any((other) => other.isEmpty);
  }

  /// Records a person so later calls to [matches] see them.
  void add(String first, String last, String number) =>
      _add(first, last, number);
}

/// Turns mapped [rows] into candidates flagged against [existing] and each
/// other. Separate first/last columns win over a full-name column; a full
/// name alone is split with [splitName].
List<RosterCandidate> buildCandidates(
  List<List<String>> rows,
  List<RosterField> mapping, {
  required Iterable<Student> existing,
}) {
  String cell(List<String> row, RosterField field) {
    final i = mapping.indexOf(field);
    return i == -1 || i >= row.length ? '' : row[i].trim();
  }

  final onRoster = RosterMatcher(existing);
  final inFile = RosterMatcher(const []);
  final out = <RosterCandidate>[];
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    var first = cell(row, RosterField.firstName);
    var last = cell(row, RosterField.lastName);
    final full = cell(row, RosterField.fullName);
    if (first.isEmpty && last.isEmpty && full.isNotEmpty) {
      (:first, :last) = splitName(full);
    }
    final number = cell(row, RosterField.studentNumber);
    final email = cell(row, RosterField.email);

    out.add(
      _candidate(
        r,
        first,
        last,
        number: number,
        email: email,
        onRoster: onRoster,
        inFile: inFile,
      ),
    );
  }
  return out;
}

/// Candidates for pasted names (no numbers or emails), flagged the same way.
List<RosterCandidate> candidatesFromNames(
  List<PersonName> names, {
  required Iterable<Student> existing,
}) {
  final onRoster = RosterMatcher(existing);
  final inFile = RosterMatcher(const []);
  return [
    for (var i = 0; i < names.length; i++)
      _candidate(
        i,
        names[i].first,
        names[i].last,
        onRoster: onRoster,
        inFile: inFile,
      ),
  ];
}

RosterCandidate _candidate(
  int row,
  String rawFirst,
  String rawLast, {
  required RosterMatcher onRoster,
  required RosterMatcher inFile,
  String number = '',
  String email = '',
}) {
  // A lone surname becomes the first name so the student always has one.
  final (first, last) = rawFirst.isEmpty ? (rawLast, '') : (rawFirst, rawLast);
  final issues = <RosterIssue>{};
  if (first.isEmpty) {
    issues.add(RosterIssue.missingName);
  } else {
    if (onRoster.matches(first, last, number)) {
      issues.add(RosterIssue.alreadyOnRoster);
    } else if (inFile.matches(first, last, number)) {
      issues.add(RosterIssue.duplicateInFile);
    }
    inFile.add(first, last, number);
  }
  return RosterCandidate(
    row: row,
    firstName: first,
    lastName: last,
    studentNumber: number,
    email: email,
    issues: issues,
  );
}
