import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/settings/settings_page.dart';
import 'package:rubric/features/settings/settings_tiles.dart';
import 'package:rubric/l10n/l10n.dart';

import '../../helpers/app_harness.dart';
import 'seed.dart';

final AppLocalizations l = lookupAppLocalizations(const Locale('en'));

/// What a fresh launch would load: the settings as written to preferences.
AppSettings persisted(TestApp app) => AppSettings.fromJson(
  jsonDecode(app.read(sharedPreferencesProvider).getString('settings.v1')!)
      as Map<String, dynamic>,
);

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapFinder(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder roundButton(String label) =>
    find.byWidgetPredicate((w) => w is SettingsRoundButton && w.label == label);

void main() {
  testWidgets('shows every section', (tester) async {
    await pumpPage(tester, const SettingsPage());
    for (final label in [
      l.settingsSectionProfile,
      l.settingsSectionGrading,
      l.settingsSectionFeedback,
      l.settingsSectionData,
      l.settingsSectionApp,
    ]) {
      await tester.ensureVisible(find.text(label.toUpperCase()));
      expect(find.text(label.toUpperCase()), findsOneWidget);
    }
  });

  testWidgets('teacher name is edited in a sheet and persists', (tester) async {
    final app = await pumpPage(tester, const SettingsPage());
    await tapText(tester, l.settingsTeacherNameEmpty);
    await tester.enterText(find.byType(TextField), '  Ms. Rivera ');
    await tapText(tester, l.settingsSave);

    expect(app.read(settingsProvider).teacherName, 'Ms. Rivera');
    expect(persisted(app).teacherName, 'Ms. Rivera');
    expect(find.text('Ms. Rivera'), findsOneWidget);
  });

  testWidgets('dismissing the name sheet keeps the old name', (tester) async {
    final app = await pumpPage(
      tester,
      const SettingsPage(),
      settings: const AppSettings(onboardingComplete: true, teacherName: 'Jo'),
    );
    await tapText(tester, 'Jo');
    await tester.enterText(find.byType(TextField), 'Someone else');
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pumpAndSettle();
    expect(app.read(settingsProvider).teacherName, 'Jo');
  });

  testWidgets('grading defaults persist', (tester) async {
    final app = await pumpPage(tester, const SettingsPage());

    await tapText(tester, l.settingsModeDetailed);
    expect(persisted(app).defaultMode, GradingMode.detailed);

    await tapText(tester, '0.00');
    expect(persisted(app).decimals, 2);
    expect(find.text(l.settingsDecimalsExample('87.46%')), findsOneWidget);

    await tapFinder(tester, roundButton(l.settingsLatePenaltyIncrease));
    expect(persisted(app).latePenaltyPercent, 15);
    await tapFinder(tester, roundButton(l.settingsLatePenaltyDecrease));
    await tapFinder(tester, roundButton(l.settingsLatePenaltyDecrease));
    expect(persisted(app).latePenaltyPercent, 5);
    expect(find.text(l.settingsLatePenaltyValue('5')), findsOneWidget);

    await tapText(tester, l.settingsLetterGradesTitle);
    expect(persisted(app).showLetterGrades, isFalse);
  });

  testWidgets('late penalty cannot go below zero', (tester) async {
    final app = await pumpPage(
      tester,
      const SettingsPage(),
      settings: const AppSettings(
        onboardingComplete: true,
        latePenaltyPercent: 0,
      ),
    );
    await tapFinder(tester, roundButton(l.settingsLatePenaltyDecrease));
    expect(persisted(app).latePenaltyPercent, 0);
  });

  testWidgets('haptics toggle persists', (tester) async {
    final app = await pumpPage(tester, const SettingsPage());
    await tapText(tester, l.settingsHapticsTitle);
    expect(persisted(app).haptics, isFalse);
    await tapText(tester, l.settingsHapticsTitle);
    expect(persisted(app).haptics, isTrue);
  });

  group('default grading scale', () {
    testWidgets('picking a preset saves it, and Undo restores the old one', (
      tester,
    ) async {
      final app = await pumpPage(tester, const SettingsPage());
      expect(find.text(l.settingsScalePresetStandard), findsOneWidget);

      await tapText(tester, l.settingsScalePresetStandard);
      await tapText(tester, l.settingsScalePresetPassFail);
      await tapText(tester, l.settingsScaleSave);

      expect(persisted(app).defaultScale, GradingScale.passFail);
      expect(find.text(l.settingsScalePresetPassFail), findsOneWidget);

      await tester.tap(find.text(l.settingsUndo));
      await tester.pumpAndSettle();
      expect(persisted(app).defaultScale, GradingScale.standard);
    });

    testWidgets('an edited band saves as a custom scale, sorted', (
      tester,
    ) async {
      final app = await pumpPage(tester, const SettingsPage());
      await tapText(tester, l.settingsScalePresetStandard);

      // Rows are (name, from%) pairs: A 90, B 80, C 70, D 60, F 0.
      await tester.enterText(find.byType(TextField).at(1), '93');
      await tester.pumpAndSettle();
      expect(find.text(l.settingsScaleTo('92.9')), findsOneWidget);
      await tapText(tester, l.settingsScaleSave);

      expect(
        persisted(app).defaultScale.bands.first,
        const LetterBand('A', 93),
      );
      expect(find.text(l.settingsScaleCustom(5)), findsOneWidget);
    });

    testWidgets('an invalid scale explains why and cannot be saved', (
      tester,
    ) async {
      final app = await pumpPage(tester, const SettingsPage());
      await tapText(tester, l.settingsScalePresetStandard);

      FilledButton save() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l.settingsScaleSave),
      );

      // F no longer starts at 0.
      await tester.enterText(find.byType(TextField).at(9), '10');
      await tester.pumpAndSettle();
      expect(find.text(l.settingsScaleIssueNoZero), findsOneWidget);
      expect(save().onPressed, isNull);

      // Two grades share a name.
      await tester.enterText(find.byType(TextField).at(9), '0');
      await tester.enterText(find.byType(TextField).at(2), 'A');
      await tester.pumpAndSettle();
      expect(find.text(l.settingsScaleIssueDuplicateName), findsOneWidget);
      expect(save().onPressed, isNull);

      // A new, empty row needs a name.
      await tester.enterText(find.byType(TextField).at(2), 'B');
      await tapText(tester, l.settingsScaleAddGrade);
      expect(find.text(l.settingsScaleIssueBlankName), findsOneWidget);

      // Removing it makes the scale valid again.
      await tester.tap(find.byTooltip(l.settingsScaleRemoveGrade(6)));
      await tester.pumpAndSettle();
      expect(find.text(l.settingsScaleIssueBlankName), findsNothing);
      expect(save().onPressed, isNotNull);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(persisted(app).defaultScale, GradingScale.standard);
    });
  });

  testWidgets('links open comment bank, backup and about', (tester) async {
    final app = await pumpPage(tester, const SettingsPage());
    for (final (title, route) in [
      (l.settingsCommentBankTitle, Routes.commentBank),
      (l.settingsBackupTitle, Routes.backup),
      (l.settingsAboutTitle, Routes.about),
    ]) {
      await tapText(tester, title);
      expect(app.visited.last, route);
      app.router.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('load sample data reports success', (tester) async {
    await pumpPage(tester, const SettingsPage());
    await tapText(tester, l.settingsSampleTitle);
    expect(find.text(l.settingsSampleLoaded), findsOneWidget);
  });

  testWidgets('replay onboarding clears the flag and goes to welcome', (
    tester,
  ) async {
    final app = await pumpPage(tester, const SettingsPage());
    await tapText(tester, l.settingsOnboardingTitle);
    expect(persisted(app).onboardingComplete, isFalse);
    expect(app.visited.last, Routes.welcome);
  });

  group('erase all data', () {
    testWidgets('after two confirmations, empties the database, resets '
        'settings and returns to welcome', (tester) async {
      final app = await pumpPage(
        tester,
        const SettingsPage(),
        seed: seedEverything,
        settings: const AppSettings(
          onboardingComplete: true,
          teacherName: 'Jo',
          decimals: 2,
        ),
      );
      await tapText(tester, l.settingsEraseTitle);
      expect(find.text(l.settingsEraseConfirmTitle), findsOneWidget);
      await tapText(tester, l.settingsEraseConfirmAction);
      expect(find.text(l.settingsEraseFinalTitle), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text(l.settingsEraseFinalAction));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      final counts = (await tester.runAsync(() => rowCounts(app.db)))!;
      expect(counts.values, everyElement(0), reason: '$counts');
      final settings = persisted(app);
      expect(settings.onboardingComplete, isFalse);
      expect(settings.teacherName, '');
      expect(settings.decimals, const AppSettings().decimals);
      expect(app.visited.last, Routes.welcome);
    });

    testWidgets('cancelling the second confirmation erases nothing', (
      tester,
    ) async {
      final app = await pumpPage(
        tester,
        const SettingsPage(),
        seed: seedEverything,
      );
      await tapText(tester, l.settingsEraseTitle);
      await tapText(tester, l.settingsEraseConfirmAction);
      await tapText(
        tester,
        MaterialLocalizations.of(tester.element(find.byType(AlertDialog)))
            .cancelButtonLabel,
      );

      final counts = (await tester.runAsync(() => rowCounts(app.db)))!;
      expect(counts.values, everyElement(greaterThan(0)));
      expect(persisted(app).onboardingComplete, isTrue);
      expect(app.visited, isEmpty);
    });
  });

  testWidgets('on a tablet the column stays readable width', (tester) async {
    await pumpPage(tester, const SettingsPage(), size: const Size(1200, 900));
    final card = find.text(l.settingsTeacherNameEmpty);
    final width = tester
        .getSize(find.ancestor(of: card, matching: find.byType(Material)).first)
        .width;
    expect(width, lessThanOrEqualTo(settingsMaxWidth));
  });
}
