import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';

/// Everything a widget test needs, with the database exposed for seeding and
/// the navigations the screen attempted recorded in [visited].
class TestApp {
  new(this.db, this.container, this.router, this.visited);

  final AppDatabase db;
  final ProviderContainer container;
  final GoRouter router;

  /// Locations pushed/gone to from the page under test (other than itself).
  final List<String> visited;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);
}

/// Pumps [page] at `/` inside the real theme, localizations, an in-memory
/// database and mock preferences. Any other location renders a placeholder and
/// is recorded in [TestApp.visited].
///
/// [seed] runs against the database BEFORE the first frame.
Future<TestApp> pumpPage(
  WidgetTester tester,
  Widget page, {
  Future<void> Function(AppDatabase db)? seed,
  AppSettings settings = const AppSettings(onboardingComplete: true),
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = testDatabase();
  addTearDown(db.close);
  if (seed != null) await tester.runAsync(() => seed(db));

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).update((_) => settings);

  final visited = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => page),
      GoRoute(
        path: '/:rest(.*)',
        builder: (context, state) {
          visited.add(state.uri.toString());
          return Scaffold(body: Text('visited ${state.uri}'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildRubricTheme(),
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return TestApp(db, container, router, visited);
}
