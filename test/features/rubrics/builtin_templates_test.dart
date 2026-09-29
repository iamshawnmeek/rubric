import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubrics/builtin_templates.dart';

void main() {
  test('the catalogue ships at least 14 templates with unique ids', () {
    expect(builtinTemplates.length, greaterThanOrEqualTo(14));
    final ids = builtinTemplates.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('it mixes simple and detailed templates across subjects', () {
    final modes = builtinTemplates.map((t) => t.rubric.mode).toSet();
    expect(modes, {GradingMode.simple, GradingMode.detailed});
    final subjects = builtinTemplates.map((t) => t.rubric.subject).toSet();
    expect(subjects.length, greaterThanOrEqualTo(5));
  });

  for (final template in builtinTemplates) {
    final rubric = template.rubric;
    group(rubric.title, () {
      test('is a ready-to-grade template', () {
        expect(rubric.issues, isEmpty);
        expect(rubric.isTemplate, isTrue);
        expect(rubric.subject.trim(), isNotEmpty);
        expect(rubric.description.trim(), isNotEmpty);
        expect(template.grades, startsWith('Grades '));
      });

      test('group weights sum to 100', () {
        expect(rubric.totalWeight, 100);
        expect(rubric.groups.every((g) => g.weight > 0), isTrue);
      });

      test('ids are unique within the template', () {
        final ids = [
          rubric.id,
          ...rubric.levels.map((l) => l.id),
          ...rubric.groups.map((g) => g.id),
          ...rubric.objectives.map((o) => o.id),
        ];
        expect(ids.toSet(), hasLength(ids.length));
      });

      test('descriptors are keyed to its own levels', () {
        final levelIds = rubric.levels.map((l) => l.id).toSet();
        for (final objective in rubric.objectives) {
          expect(
            levelIds.containsAll(objective.descriptors.keys),
            isTrue,
            reason: objective.title,
          );
          if (rubric.mode == GradingMode.detailed) {
            expect(
              objective.descriptors.keys.toSet(),
              levelIds,
              reason: '${objective.title} must describe every level',
            );
            expect(
              objective.descriptors.values.every((d) => d.trim().isNotEmpty),
              isTrue,
              reason: objective.title,
            );
          } else {
            expect(
              objective.description.trim(),
              isNotEmpty,
              reason: '${objective.title} needs a full-marks description',
            );
          }
        }
      });

      test('levels are ordered best first', () {
        final points = rubric.levels.map((l) => l.points).toList();
        expect(points, [...points]..sort((a, b) => b.compareTo(a)));
      });
    });
  }

  test('builtinTemplateById finds templates and nothing else', () {
    final first = builtinTemplates.first;
    expect(builtinTemplateById(first.id), same(first));
    expect(builtinTemplateById('not-a-template'), isNull);
  });

  test('using a template keeps every descriptor under fresh ids', () {
    final template = builtinTemplates
        .firstWhere((t) => t.rubric.mode == GradingMode.detailed)
        .rubric;
    final copy = template.duplicate(isTemplate: false);
    expect(copy.isTemplate, isFalse);
    expect(copy.id, isNot(template.id));
    expect(copy.isReady, isTrue);
    final copyLevels = copy.levels.map((l) => l.id).toSet();
    expect(
      copyLevels.intersection(template.levels.map((l) => l.id).toSet()),
      isEmpty,
    );
    for (final (i, o) in copy.objectives.indexed) {
      expect(o.descriptors.keys.toSet(), copyLevels);
      expect(
        o.descriptors.values.toList(),
        template.objectives[i].descriptors.values.toList(),
      );
    }
  });
}
