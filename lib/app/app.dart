import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harbor/harbor.dart';
import 'package:rubric/app/router.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/l10n/l10n.dart';

class RubricApp extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RubricApp> createState() => _RubricAppState();
}

class _RubricAppState extends ConsumerState<RubricApp> {
  // Coming back to the app is when another device's work is most likely
  // waiting, and when a queued change most likely has a connection again.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(syncServiceProvider)?.nudge(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildRubricTheme(),
      darkTheme: buildRubricTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Every page and sheet below floats on one sea: harbor measures what
      // covers each edge (system bars, keyboard, our CTA and nav bar) so no
      // page pads by hand.
      builder: (context, child) => HarborSea(child: child!),
    );
  }
}
