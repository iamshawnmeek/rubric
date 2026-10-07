import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:harbor/harbor.dart';
import 'package:rubric/l10n/l10n.dart';

/// Bottom navigation on phones, a rail on tablets.
///
/// Both are quays of one harbor: the branch's pages end where the bar
/// begins (and start where the rail ends), and every page inside sees the
/// bar as part of its coast, so its content clears it once. Previously a
/// Scaffold in a Scaffold, where the rail's side inset could apply twice.
class AppShell extends StatelessWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const railBreakpoint = 700.0;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final destinations = [
      (FontAwesomeIcons.house, l.navHome),
      (FontAwesomeIcons.users, l.navClasses),
      (FontAwesomeIcons.tableList, l.navRubrics),
      (FontAwesomeIcons.gear, l.navSettings),
    ];

    final wide = MediaQuery.sizeOf(context).width >= railBreakpoint;
    final theme = Theme.of(context);
    // A dock pads its child clear of the coast (the home indicator, a side
    // cutout) and paints its backdrop under the whole of its ground, so the
    // bar's colour reaches the screen's edge as NavigationBar's own did.
    Widget backdrop(Color? color) =>
        ColoredBox(color: color ?? theme.colorScheme.surfaceContainer);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Harbor(
        debugLabel: 'shell',
        start: [
          if (wide)
            HarborDock.quay(
              debugLabel: 'rail',
              backdrop: backdrop(theme.navigationRailTheme.backgroundColor),
              child: NavigationRail(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final (icon, label) in destinations)
                    NavigationRailDestination(
                      icon: FaIcon(icon, size: 20),
                      label: Text(label),
                    ),
                ],
              ),
            ),
        ],
        bottom: [
          if (!wide)
            HarborDock.quay(
              debugLabel: 'nav bar',
              backdrop: backdrop(theme.navigationBarTheme.backgroundColor),
              // Stays put under the keyboard (pilings), as a tab bar should.
              child: NavigationBar(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                destinations: [
                  for (final (icon, label) in destinations)
                    NavigationDestination(
                      icon: FaIcon(icon, size: 20),
                      label: label,
                    ),
                ],
              ),
            ),
        ],
        // The keyboard is each page's to clear (their fairways do), so the
        // shell's body runs under it rather than shrinking.
        bodyClearsTide: false,
        body: shell,
      ),
    );
  }
}
