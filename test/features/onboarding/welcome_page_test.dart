import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/app.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/home/home_page.dart';
import 'package:rubric/features/onboarding/onboarding_actions.dart';
import 'package:rubric/features/onboarding/welcome_page.dart';
import 'package:rubric/features/rubric_builder/rubric_builder_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/db.dart';

const _firstRun = AppSettings();

/// Waits out work the database does on real async (saving, seeding).
Future<void> _settleDb(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();
}

Future<void> _toLastPage(WidgetTester tester) async {
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
  expect(find.text('But first…'), findsWidgets);
}

void main() {
  testWidgets('the pager walks the three cards with Next', (tester) async {
    await pumpPage(tester, const WelcomePage(), settings: _firstRun);

    expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Page 3 of 3'), findsOneWidget);

    // The last card trades Skip for the ways out of the flow.
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Explore with sample data'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
  });

  testWidgets(
    'first objective saves a draft and opens the builder in first-run mode',
    (tester) async {
      final app = await pumpPage(
        tester,
        const WelcomePage(),
        settings: _firstRun,
      );
      await _toLastPage(tester);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Let’s create your first rubric.'), findsOneWidget);
      expect(find.text('What is your first grading objective?'), findsWidgets);

      await tester.enterText(
        find.byType(TextField),
        '  Grammar, usage and mechanics ',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel('Create rubric with this objective'),
      );
      await _settleDb(tester);

      final rubrics = await tester.runAsync(
        () => RubricRepository(app.db).all(),
      );
      final draft = rubrics!.single;
      expect(draft.groups.single.title, 'Group 1');
      expect(draft.groups.single.weight, 100);
      expect(draft.objectives.single.title, 'Grammar, usage and mechanics');
      expect(app.visited, [Routes.buildRubric(draft.id, firstRun: true)]);
      expect(
        app.visited.single,
        contains('step=${BuilderStep.objectives.name}'),
      );
      // Onboarding finishes when the builder does, not here.
      expect(app.read(settingsProvider).onboardingComplete, isFalse);
    },
  );

  testWidgets('the add button stays hidden until an objective is typed', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const WelcomePage(),
      settings: _firstRun,
    );
    await _toLastPage(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Create rubric with this objective'),
      findsNothing,
    );
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(app.visited, isEmpty, reason: 'a blank objective is not saved');
  });

  testWidgets('skip for now marks onboarding complete', (tester) async {
    final app = await pumpPage(
      tester,
      const WelcomePage(),
      settings: _firstRun,
    );
    await _toLastPage(tester);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(app.read(settingsProvider).onboardingComplete, isTrue);
    final saved = await tester.runAsync(() => RubricRepository(app.db).all());
    expect(saved, isEmpty);
  });

  testWidgets('explore with sample data loads it and completes onboarding', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const WelcomePage(),
      settings: _firstRun,
    );
    await _toLastPage(tester);

    await tester.tap(find.text('Explore with sample data'));
    await _settleDb(tester);

    expect(app.read(settingsProvider).onboardingComplete, isTrue);
    final courses = await tester.runAsync(
      () => CourseRepository(app.db).allCourses(),
    );
    expect(courses, hasLength(2));
  });

  testWidgets('in the real app, skipping lands on Home', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = testDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
        ],
        child: const RubricApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);

    await _toLastPage(tester);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomePage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);

    // Unmount so drift's stream-teardown timers fire inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  test('the first-rubric draft follows the teacher’s defaults', () {
    final draft = firstRubricDraft(
      objective: ' Thesis ',
      groupTitle: 'Group 1',
      settings: const AppSettings(
        defaultMode: GradingMode.detailed,
        defaultScale: GradingScale.plusMinus,
      ),
    );
    expect(draft.title, isEmpty);
    expect(draft.mode, GradingMode.detailed);
    expect(draft.scale, GradingScale.plusMinus);
    expect(draft.levels, hasLength(4));
    expect(draft.objectives.single.title, 'Thesis');
    expect(draft.totalWeight, 100);
  });
}
