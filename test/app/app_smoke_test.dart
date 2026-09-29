import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/app.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/features/home/home_page.dart';
import 'package:rubric/features/onboarding/welcome_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/db.dart';

Future<void> _boot(
  WidgetTester tester,
  Map<String, Object> prefsValues, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefsValues);
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
}

void main() {
  testWidgets('a first launch lands on the welcome flow', (tester) async {
    await _boot(tester, {});
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('an onboarded launch lands on Home with navigation', (
    tester,
  ) async {
    await _boot(tester, {'settings.v1': '{"onboardingComplete":true}'});
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('tablets get a navigation rail instead', (tester) async {
    await _boot(tester, {
      'settings.v1': '{"onboardingComplete":true}',
    }, size: const Size(1024, 768));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
