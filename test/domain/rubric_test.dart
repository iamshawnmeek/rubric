import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';

import '../helpers/fixtures.dart';

void main() {
  group('Rubric', () {
    test('JSON round-trips losslessly', () {
      final r = essayRubric(mode: GradingMode.detailed).copyWith(
        description: 'Five-paragraph essay',
        subject: 'English',
        scale: GradingScale.plusMinus,
        isTemplate: true,
      );
      expect(Rubric.fromJson(r.toJson()), r);
    });

    test('a well-formed rubric has no issues', () {
      expect(essayRubric().issues, isEmpty);
      expect(essayRubric().isReady, isTrue);
    });

    test('reports each issue', () {
      final r = essayRubric().copyWith(
        title: ' ',
        groups: [const RubricGroup(id: 'x', title: 'Empty', weight: 50)],
      );
      expect(
        r.issues,
        containsAll([
          RubricIssue.noTitle,
          RubricIssue.emptyGroup,
          RubricIssue.weightsNotHundred,
        ]),
      );
      expect(
        essayRubric(mode: GradingMode.detailed).copyWith(levels: []).issues,
        contains(RubricIssue.noLevels),
      );
      expect(
        essayRubric(mode: GradingMode.detailed)
            .copyWith(
              levels: const [
                PerformanceLevel(id: 'a', label: 'A', points: 2),
                PerformanceLevel(id: 'b', label: 'B', points: 2),
              ],
            )
            .issues,
        contains(RubricIssue.duplicateLevelPoints),
      );
      expect(
        essayRubric().copyWith(groups: []).issues,
        contains(RubricIssue.noGroups),
      );
    });

    test('duplicate gives fresh ids and remaps descriptor level ids', () {
      final original = essayRubric(mode: GradingMode.detailed);
      final copy = original.duplicate(title: 'Essay (copy)', now: t0);
      expect(copy.id, isNot(original.id));
      expect(copy.title, 'Essay (copy)');
      expect(copy.objectives.map((o) => o.id), isNot(contains('o1')));
      expect(copy.levels.map((l) => l.id), isNot(contains('L4')));
      final grammar = copy.objectives.first;
      final topLevel = copy.levels.first;
      expect(grammar.descriptors, {topLevel.id: 'Flawless'});
      expect(
        copy.objectives.map((o) => o.title),
        original.objectives.map((o) => o.title),
      );
      expect(copy.groups.map((g) => g.weight), [60, 40]);
    });

    test('lookups', () {
      final r = essayRubric();
      expect(r.objectives, hasLength(3));
      expect(r.totalWeight, 100);
      expect(r.groupOf('o3')?.id, 'g2');
      expect(r.groupOf('nope'), isNull);
      expect(r.maxLevelPoints, 4);
      expect(r.levelById('L2')?.label, 'Developing');
    });
  });

  group('GradingScale', () {
    test('maps boundaries inclusively', () {
      const s = GradingScale.standard;
      expect(s.letterFor(100), 'A');
      expect(s.letterFor(90), 'A');
      expect(s.letterFor(89.99), 'B');
      expect(s.letterFor(60), 'D');
      expect(s.letterFor(59.9), 'F');
      expect(s.letterFor(0), 'F');
      expect(s.letterFor(-5), 'F');
    });

    test('sorts bands and round-trips', () {
      final s = GradingScale.sorted(const [
        LetterBand('F', 0),
        LetterBand('A', 90),
        LetterBand('C', 70),
      ]);
      expect(s.bands.map((b) => b.letter), ['A', 'C', 'F']);
      expect(GradingScale.fromJson(s.toJson()), s);
      expect(s.upperBoundOf(0), 100);
      expect(s.upperBoundOf(1), closeTo(89.9, 1e-9));
    });

    test('validates', () {
      expect(GradingScale.standard.problem, isNull);
      expect(GradingScale.plusMinus.problem, isNull);
      expect(const GradingScale([]).problem, isNotNull);
      expect(const GradingScale([LetterBand('A', 50)]).problem, isNotNull);
      expect(
        const GradingScale([LetterBand('A', 50), LetterBand('A', 0)]).problem,
        isNotNull,
      );
      expect(
        const GradingScale([LetterBand('A', 0), LetterBand('B', 0)]).problem,
        isNotNull,
      );
      expect(const GradingScale([LetterBand('', 0)]).problem, isNotNull);
    });
  });

  group('Evaluation', () {
    test('JSON round-trips both score kinds', () {
      final e =
          eval(
            {'o1': const PercentScore(82.5), 'o2': const LevelScore('L3')},
            penalty: 10,
            override: 77,
          ).copyWith(
            comment: 'Nice work',
            objectiveComments: {'o1': 'Watch commas'},
            late: true,
            updatedAt: t0,
          );
      expect(Evaluation.fromJson(e.toJson()), e);
    });

    test('withScore sets and clears', () {
      final e = eval({}).withScore('o1', const PercentScore(10));
      expect(e.scores['o1'], const PercentScore(10));
      expect(e.withScore('o1', null).scores, isEmpty);
    });

    test('rejects unknown score types', () {
      expect(
        () => ObjectiveScore.fromJson(const {'type': 'bogus'}),
        throwsFormatException,
      );
    });
  });
}
