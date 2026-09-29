import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';
import 'package:rubric/features/rubric_builder/rubric_draft_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/db.dart';
import '../../helpers/fixtures.dart';

void main() {
  late ProviderContainer container;

  Future<RubricDraftNotifier> open(
    String id, {
    Rubric? seed,
    AppSettings settings = const AppSettings(),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testDatabase();
    addTearDown(db.close);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).update((_) => settings);
    if (seed != null) await container.read(rubricRepositoryProvider).save(seed);
    // Keep the auto-dispose family alive for the whole test.
    container.listen(rubricDraftProvider(id), (_, _) {});
    await container.read(rubricDraftProvider(id).future);
    final notifier = container.read(rubricDraftProvider(id).notifier);
    return notifier;
  }

  RubricDraft draftOf(String id) =>
      container.read(rubricDraftProvider(id)).requireValue!;

  List<String> titles(List<Objective> objectives) => [
    for (final o in objectives) o.title,
  ];

  List<int> weights(RubricDraft d) => [
    for (final g in d.rubric.groups) g.weight,
  ];

  group('a new rubric', () {
    test('is seeded from the default mode and scale in settings', () async {
      await open(
        newRubricId,
        settings: const AppSettings(
          defaultMode: GradingMode.detailed,
          defaultScale: GradingScale.passFail,
        ),
      );
      final draft = draftOf(newRubricId);
      expect(draft.isNew, isTrue);
      expect(draft.rubric.mode, GradingMode.detailed);
      expect(draft.rubric.scale, GradingScale.passFail);
      expect(draft.rubric.levels, hasLength(4));
      expect(draft.isDirty, isFalse);
    });
  });

  group('objectives', () {
    test('add, rename and remove', () async {
      final n = await open(newRubricId);
      final grammar = n.addObjective('  Grammar ')!;
      n.addObjective('Sources');
      expect(n.addObjective('   '), isNull);
      expect(titles(draftOf(newRubricId).ungrouped), ['Grammar', 'Sources']);
      expect(draftOf(newRubricId).isDirty, isTrue);

      n.updateObjective(grammar.id, title: 'Mechanics', description: 'Commas');
      expect(draftOf(newRubricId).ungrouped.first.title, 'Mechanics');
      expect(draftOf(newRubricId).ungrouped.first.description, 'Commas');

      n.updateObjective(grammar.id, title: ' ');
      expect(
        draftOf(newRubricId).ungrouped.first.title,
        'Mechanics',
        reason: 'a blank rename is ignored',
      );

      final removed = n.removeObjective(grammar.id)!;
      expect(titles(draftOf(newRubricId).ungrouped), ['Sources']);
      n.restoreObjective(removed);
      expect(titles(draftOf(newRubricId).ungrouped), ['Mechanics', 'Sources']);
    });

    test('reorder moves freely in the tray', () async {
      final n = await open(newRubricId);
      ['A', 'B', 'C'].forEach(n.addObjective);
      n.reorderObjective(0, 2);
      expect(titles(draftOf(newRubricId).objectives), ['B', 'C', 'A']);
      n.reorderObjective(2, 0);
      expect(titles(draftOf(newRubricId).objectives), ['A', 'B', 'C']);
    });

    test('reorder keeps an objective inside its own group', () async {
      final n = await open('r1', seed: essayRubric());
      // Grammar, Organization | Sources — drag Grammar to the very end.
      n.reorderObjective(0, 2);
      final d = draftOf('r1');
      expect(titles(d.rubric.groups[0].objectives), [
        'Organization',
        'Grammar',
      ]);
      expect(titles(d.rubric.groups[1].objectives), ['Sources']);
    });

    test('removing the last objective of a group drops the group and undo '
        'brings back the group with its old weight', () async {
      final n = await open('r1', seed: essayRubric());
      final removed = n.removeObjective('o3')!;
      var d = draftOf('r1');
      expect(d.rubric.groups.map((g) => g.id), ['g1']);
      expect(weights(d), [100]);

      n.restoreObjective(removed);
      d = draftOf('r1');
      expect(d.rubric.groups.map((g) => g.id), ['g1', 'g2']);
      expect(weights(d), [60, 40]);
      expect(d.rubric.groups[1].objectives.single.id, 'o3');
      expect(d.isDirty, isFalse, reason: 'undo restores the saved rubric');
    });
  });

  group('grouping', () {
    test('new groups take an even share and keep sums at 100', () async {
      final n = await open(newRubricId);
      final a = n.addObjective('A')!;
      final b = n.addObjective('B')!;
      final c = n.addObjective('C')!;

      n.moveToNewGroup(a.id, title: 'Group 1');
      expect(weights(draftOf(newRubricId)), [100]);
      n.moveToNewGroup(b.id, title: 'Group 2');
      expect(weights(draftOf(newRubricId)), [50, 50]);
      n.moveObjective(c.id, groupId: draftOf(newRubricId).rubric.groups[0].id);

      final d = draftOf(newRubricId);
      expect(d.ungrouped, isEmpty);
      expect(titles(d.rubric.groups[0].objectives), ['A', 'C']);
      expect(d.rubric.totalWeight, 100);
    });

    test('moving the last objective out of a group removes it', () async {
      final n = await open('r1', seed: essayRubric());
      n.moveObjective('o3', groupId: 'g1');
      final d = draftOf('r1');
      expect(d.rubric.groups.map((g) => g.id), ['g1']);
      expect(titles(d.rubric.groups.single.objectives), [
        'Grammar',
        'Organization',
        'Sources',
      ]);
      expect(weights(d), [100]);
    });

    test('moving to the tray and to an unknown group', () async {
      final n = await open('r1', seed: essayRubric());
      n.moveObjective('o1', groupId: 'nope');
      expect(draftOf('r1').rubric.objectives, hasLength(3));

      n.moveObjective('o1');
      final d = draftOf('r1');
      expect(titles(d.ungrouped), ['Grammar']);
      expect(d.rubric.totalWeight, 100);
      expect(d.isComplete, isFalse);
    });

    test('a new group beside existing ones keeps their proportions', () async {
      final n = await open('r1', seed: essayRubric());
      n.moveToNewGroup('o2', title: 'Style');
      final d = draftOf('r1');
      expect(d.rubric.groups.map((g) => g.title), [
        'Writing',
        'Research',
        'Style',
      ]);
      expect(d.rubric.totalWeight, 100);
      expect(weights(d)[0], greaterThan(weights(d)[1]));
    });

    test('group everything and remove a group', () async {
      final n = await open(newRubricId);
      ['A', 'B', 'C'].forEach(n.addObjective);
      n.groupEverything(title: 'All');
      var d = draftOf(newRubricId);
      expect(d.ungrouped, isEmpty);
      expect(d.rubric.groups.single.title, 'All');
      expect(titles(d.rubric.objectives), ['A', 'B', 'C']);
      expect(weights(d), [100]);

      n.removeGroup(d.rubric.groups.single.id);
      d = draftOf(newRubricId);
      expect(d.rubric.groups, isEmpty);
      expect(titles(d.ungrouped), ['A', 'B', 'C']);
    });

    test('renaming a group', () async {
      final n = await open('r1', seed: essayRubric());
      n.renameGroup('g2', 'Evidence');
      expect(draftOf('r1').rubric.groups[1].title, 'Evidence');
      n.renameGroup('g2', '  ');
      expect(draftOf('r1').isComplete, isFalse);
    });
  });

  group('weights', () {
    Future<RubricDraftNotifier> threeGroups() async {
      final n = await open(newRubricId);
      for (final t in ['A', 'B', 'C']) {
        n.moveToNewGroup(n.addObjective(t)!.id, title: t);
      }
      return n;
    }

    test('dragging a boundary moves weight and keeps 100', () async {
      final n = await threeGroups();
      expect(weights(draftOf(newRubricId)), [34, 33, 33]);
      n.moveBoundary(0, 10);
      expect(weights(draftOf(newRubricId)), [44, 23, 33]);
      n.moveBoundary(0, -500);
      final w = weights(draftOf(newRubricId));
      expect(w.reduce((a, b) => a + b), 100);
      expect(w[0], 1);
    });

    test('a locked group is skipped when dragging', () async {
      final n = await threeGroups();
      n
        ..toggleLock(draftOf(newRubricId).rubric.groups[1].id)
        ..moveBoundary(0, 10);
      expect(weights(draftOf(newRubricId)), [44, 33, 23]);
      n.toggleLock(draftOf(newRubricId).rubric.groups[1].id);
      expect(draftOf(newRubricId).locked, isEmpty);
    });

    test('typing an exact weight and splitting evenly', () async {
      final n = await threeGroups();
      final ids = draftOf(newRubricId).rubric.groups.map((g) => g.id).toList();
      n
        ..toggleLock(ids[2])
        ..setWeight(ids[0], 50);
      expect(weights(draftOf(newRubricId)), [50, 17, 33]);

      n.evenSplit();
      expect(weights(draftOf(newRubricId)), [34, 33, 33]);
      expect(draftOf(newRubricId).locked, isEmpty);
    });

    test('changing the groups clears locks', () async {
      final n = await threeGroups();
      final d = draftOf(newRubricId);
      n
        ..toggleLock(d.rubric.groups[0].id)
        ..moveObjective(
          d.rubric.groups[2].objectives.single.id,
          groupId: d.rubric.groups[1].id,
        );
      expect(draftOf(newRubricId).locked, isEmpty);
      expect(weights(draftOf(newRubricId)).reduce((a, b) => a + b), 100);
    });

    test('fitWeights never leaves a group at 0', () {
      expect(fitWeights([99, 1, 0.1]), [98, 1, 1]);
      expect(fitWeights([0, 0]), [50, 50]);
      expect(fitWeights([60, 40]), [60, 40]);
    });
  });

  group('scale and levels', () {
    test('band edits validate against the sorted scale', () async {
      final n = await open(newRubricId);
      n.updateBand(4, min: 55);
      expect(
        draftOf(newRubricId).sortedScale.problem,
        'The lowest grade must start at 0.',
      );
      n.addBand();
      var bands = draftOf(newRubricId).rubric.scale.bands;
      expect(bands.last, const LetterBand('', 0));
      expect(draftOf(newRubricId).sortedScale.problem, isNotNull);
      n.updateBand(5, letter: 'E');
      expect(draftOf(newRubricId).sortedScale.problem, isNull);

      n.removeBand(5);
      bands = draftOf(newRubricId).rubric.scale.bands;
      expect(bands.map((b) => b.letter), ['A', 'B', 'C', 'D', 'F']);
      n.applyScale(GradingScale.passFail);
      expect(draftOf(newRubricId).rubric.scale, GradingScale.passFail);
    });

    test('removing a level removes only its descriptors', () async {
      final n = await open('r1', seed: essayRubric(mode: GradingMode.detailed));
      n
        ..setDescriptor('o1', 'L3', 'Few errors')
        ..setDescriptor('o3', 'L4', 'Primary sources')
        ..removeLevel('L4');
      final d = draftOf('r1');
      expect(d.rubric.levels.map((l) => l.id), ['L3', 'L2', 'L1']);
      expect(d.rubric.objectives[0].descriptors, {'L3': 'Few errors'});
      expect(d.rubric.objectives[2].descriptors, isEmpty);
    });

    test(
      'reordering and relabelling levels keeps descriptors keyed by id',
      () async {
        final n = await open(
          'r1',
          seed: essayRubric(mode: GradingMode.detailed),
        );
        n
          ..moveLevel('L1', -3)
          ..updateLevel('L4', label: 'Mastery', points: 5);
        final d = draftOf('r1');
        expect(d.rubric.levels.map((l) => l.id), ['L1', 'L4', 'L3', 'L2']);
        expect(d.rubric.levelById('L4')!.label, 'Mastery');
        expect(d.rubric.objectives.first.descriptors, {'L4': 'Flawless'});

        n.setDescriptor('o1', 'L4', '  ');
        expect(draftOf('r1').rubric.objectives.first.descriptors, isEmpty);
      },
    );

    test('new levels do not collide on points', () async {
      final n = await open('r1', seed: essayRubric(mode: GradingMode.detailed));
      n.addLevel('Missing');
      expect(draftOf('r1').rubric.levels.last.points, 0);
      n.addLevel('Beyond');
      final d = draftOf('r1');
      expect(d.rubric.levels.first.label, 'Beyond');
      expect(d.rubric.levels.first.points, 5);
      expect(
        d.rubric.issues,
        isNot(contains(RubricIssue.duplicateLevelPoints)),
      );
    });

    test('switching to detailed seeds levels when there are none', () async {
      final n = await open(
        'r1',
        seed: essayRubric().copyWith(levels: const []),
      );
      n.setMode(GradingMode.detailed);
      expect(draftOf('r1').rubric.levels, hasLength(4));
    });
  });

  group('saving', () {
    test('writes a sorted, trimmed rubric and resets dirtiness', () async {
      final n = await open(newRubricId);
      n.moveToNewGroup(n.addObjective('Grammar')!.id, title: ' Writing ');
      n
        ..setDetails(title: ' Essay ', subject: 'English')
        ..applyScale(
          const GradingScale([LetterBand('F', 0), LetterBand('P', 60)]),
        );
      expect(draftOf(newRubricId).isComplete, isTrue);

      final saved = await n.save();
      final stored = await container
          .read(rubricRepositoryProvider)
          .get(saved.id);
      expect(stored!.title, 'Essay');
      expect(stored.groups.single.title, 'Writing');
      expect(stored.scale.bands.first.letter, 'P');
      final d = draftOf(newRubricId);
      expect(d.isNew, isFalse);
      expect(d.isDirty, isFalse);
    });

    test('a missing rubric resolves to null', () async {
      await open('gone');
      expect(container.read(rubricDraftProvider('gone')).value, isNull);
    });
  });
}
