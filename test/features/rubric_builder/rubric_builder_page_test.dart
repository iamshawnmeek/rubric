import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_builder_page.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fixtures.dart';

Finder _field(String hint) =>
    find.ancestor(of: find.text(hint), matching: find.byType(TextField));

Future<Rubric?> _stored(WidgetTester tester, TestApp app, String id) =>
    tester.runAsync<Rubric?>(() => app.read(rubricRepositoryProvider).get(id));

Future<void> _addObjective(WidgetTester tester, String title) async {
  await tester.tap(find.byType(CreateCard));
  await tester.pumpAndSettle();
  await tester.enterText(
    _field('example: Grammar, usage and mechanics'),
    title,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Add objective'));
  await tester.pumpAndSettle();
}

/// Scrolls the builder until [finder] is built and on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await _reveal(tester, find.text(text));
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String label) =>
    tester
        .widget<AccentButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AccentButton),
          ),
        )
        .onTap !=
    null;

Rubric _firstRunRubric() => Rubric(
  id: 'first',
  title: '',
  createdAt: t0,
  updatedAt: t0,
  levels: PerformanceLevel.defaults(),
  groups: const [
    RubricGroup(
      id: 'g1',
      title: 'Group 1',
      weight: 100,
      objectives: [Objective(id: 'o1', title: 'Thesis')],
    ),
  ],
);

void main() {
  testWidgets('a new rubric is built step by step and saved', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'new'),
    );

    expect(find.text('Grading Objectives'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('What will you grade?'), findsOneWidget);
    expect(_enabled(tester, 'Next'), isFalse);

    await _addObjective(tester, 'Grammar');
    await _addObjective(tester, 'Sources');
    expect(find.text('Objective 1'), findsOneWidget);
    expect(find.text('Objective 2'), findsOneWidget);
    expect(_enabled(tester, 'Next'), isTrue);

    await _tapText(tester, 'Next');
    expect(find.text('Assign Groups'), findsOneWidget);
    expect(find.text('2 objectives to group'), findsOneWidget);
    expect(find.text('Next'), findsNothing, reason: 'the tray replaces Next');

    await _tapText(tester, 'Put everything in one group');
    expect(find.text('Group 1'), findsOneWidget);
    expect(find.text('2 objectives to group'), findsNothing);

    await _tapText(tester, 'Next');
    expect(find.text('Assign Weights'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await _tapText(tester, 'Next');
    expect(find.text('Grading Scale'), findsOneWidget);
    await _tapText(tester, 'Set Grading Scale');

    expect(find.text('Review & Save'), findsOneWidget);
    expect(find.text('Give your rubric a title.'), findsOneWidget);
    expect(_enabled(tester, 'Save Rubric'), isFalse);

    await tester.enterText(_field('Rubric title (required)'), 'Essay');
    await tester.pumpAndSettle();
    expect(find.text('Give your rubric a title.'), findsNothing);

    await _tapText(tester, 'Save Rubric');

    final rubrics = await tester.runAsync(
      () => app.read(rubricRepositoryProvider).all(),
    );
    final saved = rubrics!.single;
    expect(saved.title, 'Essay');
    expect(saved.groups.single.title, 'Group 1');
    expect(saved.groups.single.weight, 100);
    expect(saved.objectives.map((o) => o.title), ['Grammar', 'Sources']);
    expect(app.visited, ['/rubrics/${saved.id}']);
  });

  testWidgets('objectives are dragged from the tray into groups', (
    tester,
  ) async {
    await pumpPage(tester, const RubricBuilderPage(rubricId: 'new'));
    await _addObjective(tester, 'Grammar');
    await _tapText(tester, 'Next');

    final card = find.text('Grammar');
    final target = find.text('Drag objective here');
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Group 1'), findsOneWidget);
    expect(find.text('Add to Group 1'), findsOneWidget);
    expect(find.text('1 objective to group'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('tapping an objective moves it without dragging', (tester) async {
    await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'r1', step: BuilderStep.groups),
      seed: (db) => RubricRepository(db).save(essayRubric()),
    );

    await _tapText(tester, 'Sources');
    expect(find.text('Move “Sources” to'), findsOneWidget);
    await _tapText(tester, 'Writing');

    // Research emptied out and was removed.
    expect(find.text('Add to Research'), findsNothing);
    expect(find.text('Add to Writing'), findsOneWidget);
  });

  testWidgets('deleting an objective can be undone', (tester) async {
    await pumpPage(tester, const RubricBuilderPage(rubricId: 'new'));
    await _addObjective(tester, 'Grammar');
    await _addObjective(tester, 'Sources');

    await tester.drag(find.text('Grammar'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Grammar'), findsNothing);
    expect(find.text('Deleted “Grammar”'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Grammar'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Grammar')).dy,
      lessThan(tester.getTopLeft(find.text('Sources')).dy),
      reason: 'restored in its old place',
    );
  });

  testWidgets('leaving with unsaved changes asks before discarding', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'new'),
    );
    await _addObjective(tester, 'Grammar');

    await tester.tap(find.byType(BackChevron));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Grammar'), findsOneWidget);
    expect(app.visited, isEmpty);

    await tester.tap(find.byType(BackChevron));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(app.visited, ['/rubrics']);
  });

  testWidgets('editing an existing rubric autosaves when the step changes', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'r1'),
      seed: (db) => RubricRepository(db).save(essayRubric()),
    );

    expect(find.text('In Writing'), findsWidgets);
    await tester.tap(find.text('Grammar'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Objective'), findsOneWidget);
    await tester.enterText(
      _field('example: Grammar, usage and mechanics'),
      'Mechanics',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save objective'));
    await tester.pumpAndSettle();

    await _tapText(tester, 'Next');
    expect(find.text('Assign Groups'), findsOneWidget);
    final stored = await _stored(tester, app, 'r1');
    expect(stored!.objectives.first.title, 'Mechanics');
  });

  testWidgets('a deep link to weights edits just the weights', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'r1', step: BuilderStep.weights),
      seed: (db) => RubricRepository(db).save(essayRubric()),
    );

    expect(find.text('Assign Weights'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);

    await _tapText(tester, 'Even split');
    expect(find.text('50%'), findsNWidgets(2));

    await _tapText(tester, 'Save Changes');
    final stored = await _stored(tester, app, 'r1');
    expect(stored!.groups.map((g) => g.weight), [50, 50]);
    expect(app.visited, ['/rubrics/r1']);
  });

  testWidgets('dragging the handle moves weight to the group above', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'r1', step: BuilderStep.weights),
      seed: (db) => RubricRepository(db).save(essayRubric()),
    );

    final handle = find.byKey(const ValueKey('weight-handle-0'));
    await _reveal(tester, handle);
    await tester.drag(handle, const Offset(0, 60));
    await tester.pumpAndSettle();

    expect(find.text('60%'), findsNothing);
    final percents = tester
        .widgetList<BodyOneWeights>(find.byType(BodyOneWeights))
        .map((w) => int.parse(w.data.replaceAll('%', '')))
        .toList();
    expect(percents.first, greaterThan(60));
    expect(percents.reduce((a, b) => a + b), 100);
  });

  testWidgets('typing an exact weight', (tester) async {
    await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'r1', step: BuilderStep.weights),
      seed: (db) => RubricRepository(db).save(essayRubric()),
    );

    await tester.tap(find.text('60%'));
    await tester.pumpAndSettle();
    expect(find.text('Weight for Writing'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '75');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Weight'));
    await tester.pumpAndSettle();

    expect(find.text('75%'), findsOneWidget);
    // Research is short now, so it uses the one-line layout.
    expect(find.text('25%: Research'), findsOneWidget);
  });

  testWidgets('detailed rubrics edit levels and descriptors', (tester) async {
    final app = await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'r1', step: BuilderStep.scale),
      seed: (db) =>
          RubricRepository(db).save(essayRubric(mode: GradingMode.detailed)),
    );

    await _reveal(tester, find.text('PERFORMANCE LEVELS'));
    await _reveal(tester, find.text('DESCRIPTORS'));

    final sourcesExemplary = find.bySemanticsLabel(
      RegExp('^Sources, Exemplary'),
    );
    await _reveal(tester, sourcesExemplary);
    await tester.enterText(
      find.descendant(of: sourcesExemplary, matching: find.byType(TextField)),
      'Cites primary sources',
    );
    await tester.pumpAndSettle();

    await _tapText(tester, 'Save Changes');
    final stored = await _stored(tester, app, 'r1');
    expect(stored!.objectives.last.descriptors, {
      'L4': 'Cites primary sources',
    });
  });

  testWidgets('a broken grading scale blocks the step with a reason', (
    tester,
  ) async {
    await pumpPage(tester, const RubricBuilderPage(rubricId: 'new'));
    await _addObjective(tester, 'Grammar');
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Put everything in one group');
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');

    await _tapText(tester, 'Pass / fail');
    expect(find.text('Pass'), findsWidgets);
    await _reveal(tester, find.bySemanticsLabel(RegExp('^Fail starts at')));
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsLabel(RegExp('^Fail starts at')),
        matching: find.byType(TextField),
      ),
      '10',
    );
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('The lowest grade must start at 0.'));
    expect(_enabled(tester, 'Set Grading Scale'), isFalse);
  });

  testWidgets('finishing first run completes onboarding and goes home', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'first', firstRun: true),
      settings: const AppSettings(),
      seed: (db) => RubricRepository(db).save(_firstRunRubric()),
    );

    expect(find.text('Thesis'), findsOneWidget);
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');
    await _tapText(tester, 'Set Grading Scale');
    await tester.enterText(_field('Rubric title (required)'), 'My first');
    await tester.pumpAndSettle();
    await _tapText(tester, 'Save Rubric');

    expect(app.read(settingsProvider).onboardingComplete, isTrue);
    final stored = await _stored(tester, app, 'first');
    expect(stored!.title, 'My first');
  });

  testWidgets('a rubric that no longer exists says so', (tester) async {
    await pumpPage(tester, const RubricBuilderPage(rubricId: 'gone'));
    expect(find.text('Rubric not found'), findsWidgets);
    expect(find.text('Back to Rubrics'), findsOneWidget);
  });

  testWidgets('review links each problem back to its step', (tester) async {
    await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'r1', step: BuilderStep.review),
      seed: (db) => RubricRepository(db).save(
        essayRubric().copyWith(
          groups: [
            essayRubric().groups[0].copyWith(weight: 70),
            essayRubric().groups[1],
          ],
        ),
      ),
    );

    expect(
      find.text('Group weights add up to 110%, not 100%.'),
      findsOneWidget,
    );
    expect(_enabled(tester, 'Save Rubric'), isFalse);
    await _tapText(tester, 'Group weights add up to 110%, not 100%.');
    expect(find.text('Assign Weights'), findsOneWidget);
  });

  testWidgets('content stays a readable column on tablets', (tester) async {
    await pumpPage(
      tester,
      const RubricBuilderPage(rubricId: 'new'),
      size: const Size(1024, 768),
    );
    expect(tester.getSize(find.byType(RubricPage)).width, 720);
  });
}
