import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubrics/library_filter.dart';

import '../../helpers/fixtures.dart';

Rubric _r(String id, String title, String subject) =>
    essayRubric().duplicate(title: title).copyWith(subject: subject);

void main() {
  final rubrics = [
    _r('a', 'Persuasive Essay', 'English'),
    _r('b', 'Lab Report', 'Biology'),
    _r('c', 'Narrative Writing', 'english '),
    _r('d', 'Exit Ticket', ''),
  ];

  test('subjectsOf dedupes ignoring case and whitespace, sorted', () {
    expect(subjectsOf(rubrics), ['Biology', 'English']);
    expect(subjectsOf(const []), isEmpty);
  });

  test('filterRubrics matches every query word in title or subject', () {
    List<String> titles(List<Rubric> list) => list.map((r) => r.title).toList();
    expect(titles(filterRubrics(rubrics)), hasLength(4));
    expect(titles(filterRubrics(rubrics, query: 'essay')), [
      'Persuasive Essay',
    ]);
    expect(titles(filterRubrics(rubrics, query: 'BIO')), ['Lab Report']);
    expect(titles(filterRubrics(rubrics, query: '  english   writing ')), [
      'Narrative Writing',
    ]);
    expect(filterRubrics(rubrics, query: 'essay biology'), isEmpty);
  });

  test('filterRubrics narrows by subject, ignoring case', () {
    expect(filterRubrics(rubrics, subject: 'English').map((r) => r.title), [
      'Persuasive Essay',
      'Narrative Writing',
    ]);
    expect(
      filterRubrics(
        rubrics,
        subject: 'English',
        query: 'narr',
      ).map((r) => r.title),
      ['Narrative Writing'],
    );
  });

  test('matchesQuery also searches the extra text', () {
    expect(matchesQuery(rubrics[1], 'grades 9', extra: 'Grades 9–12'), isTrue);
    expect(matchesQuery(rubrics[1], 'grades 9'), isFalse);
  });

  test('usageCount counts assignments created from the rubric', () {
    Assignment made(String? source) => Assignment(
      id: 'a-$source',
      courseId: 'c1',
      title: 'A',
      rubric: essayRubric(),
      sourceRubricId: source,
      createdAt: t0,
    );
    final list = [made('r1'), made('r1'), made('r2'), made(null)];
    expect(usageCount(list, 'r1'), 2);
    expect(usageCount(list, 'other'), 0);
  });

  test('formatNumber drops a trailing .0', () {
    expect(formatNumber(90), '90');
    expect(formatNumber(89.9), '89.9');
    expect(formatNumber(4), '4');
  });
}
