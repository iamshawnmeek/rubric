import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/features/settings/about_page.dart';
import 'package:rubric/features/settings/app_info.dart';
import 'package:rubric/l10n/l10n.dart';

import '../../helpers/app_harness.dart';

final AppLocalizations l = lookupAppLocalizations(const Locale('en'));

void main() {
  testWidgets('shows version, story, credits and the privacy promise', (
    tester,
  ) async {
    await pumpPage(tester, const AboutPage());
    expect(find.text(l.settingsAboutVersion(appVersion)), findsOneWidget);
    expect(find.text('Version 2.0.0'), findsOneWidget);
    expect(find.text(l.settingsAboutStoryTitle), findsOneWidget);
    expect(find.text('Designed by the Rubric founding team'), findsOneWidget);
    await tester.ensureVisible(find.text(l.settingsAboutPrivacyTitle));
    expect(find.text('All data stays on this device'), findsOneWidget);
  });

  testWidgets('Licenses opens the license page', (tester) async {
    await pumpPage(tester, const AboutPage());
    final licenses = find.text(l.settingsAboutLicensesTitle);
    await tester.ensureVisible(licenses);
    await tester.pumpAndSettle();
    await tester.tap(licenses);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
