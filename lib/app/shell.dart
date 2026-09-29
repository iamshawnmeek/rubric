import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/l10n/l10n.dart';

/// Bottom navigation on phones, a rail on tablets.
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

    if (MediaQuery.sizeOf(context).width >= railBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
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
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final (icon, label) in destinations)
            NavigationDestination(icon: FaIcon(icon, size: 20), label: label),
        ],
      ),
    );
  }
}
