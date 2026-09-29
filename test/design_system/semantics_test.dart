import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/l10n/l10n.dart';

// Every custom tappable in the design system must expose a TAP ACTION to
// assistive tech. The components wrap their content in
// Semantics(excludeSemantics: true) to give one clean label, and that also
// drops the child InkWell's action — so a screen-reader user heard "button"
// and could not press it. Reported by the classes Crawler, 2026-09-29.

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildRubricTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  final cases = <String, Widget Function(VoidCallback)>{
    'RubricCard': (t) =>
        RubricCard(cardHintText: 'Hint', cardTitleText: 'Label', onTap: t),
    'CreateCard': (t) => CreateCard(onPressed: t, label: 'Label'),
    'AccentButton': (t) => AccentButton(label: 'Label', onTap: t),
    'RubricLock': (t) => RubricLock(onTap: t, isActive: false),
    'DashedBox': (t) => DashedBox(label: 'Label', onTap: t),
    'RubricChip': (t) => RubricChip(label: 'Label', onTap: t),
    'BackChevron': (t) => BackChevron(onTap: t),
    'SegmentedToggle': (t) => SegmentedToggle<int>(
      segments: const {0: 'Zero', 1: 'Label'},
      selected: 0,
      onChanged: (_) => t(),
    ),
  };

  for (final MapEntry(key: name, value: build) in cases.entries) {
    testWidgets('$name exposes a working tap action', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(tester, build(() => taps++));

      // Population control: the component rendered and has a labelled node.
      expect(
        find.bySemanticsLabel(RegExp('Label|Lock|Back')),
        findsWidgets,
        reason: '$name rendered no labelled semantics node',
      );
      final tappable = find.semantics.byAction(SemanticsAction.tap);
      expect(tappable, findsAny, reason: '$name has no node with a tap action');

      tester.semantics.tap(tappable.last);
      await tester.pump();
      expect(taps, 1, reason: 'the tap action of $name did not reach onTap');
      handle.dispose();
    });
  }

  testWidgets('RubricCard keeps an interactive trailing widget reachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      RubricCard(
        cardHintText: 'Hint',
        cardTitleText: 'Title',
        onTap: () {},
        trailing: IconButton(
          tooltip: 'More',
          onPressed: () {},
          icon: const Icon(Icons.more_vert),
        ),
      ),
    );
    // Its own node, with its own tap — not merged into (or hidden by) the card.
    final more = tester.getSemantics(find.byTooltip('More'));
    final card = tester.getSemantics(find.bySemanticsLabel('Hint, Title'));
    expect(more.id, isNot(card.id));
    expect(more.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}
