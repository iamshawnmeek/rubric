import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/settings/comment_bank_page.dart';

import '../../helpers/app_harness.dart';

const _bank = [
  CommentSnippet(
    id: 'k1',
    text: 'Strong thesis.',
    category: 'Praise',
    useCount: 2,
  ),
  CommentSnippet(
    id: 'k2',
    text: 'Cite your sources.',
    category: 'Research',
    useCount: 9,
  ),
  CommentSnippet(id: 'k3', text: 'Proofread before submitting.'),
];

Future<List<CommentSnippet>> _all(WidgetTester tester, TestApp app) async =>
    (await tester.runAsync(() => CommentRepository(app.db).all()))!;

Future<TestApp> _pump(
  WidgetTester tester, {
  List<CommentSnippet> snippets = _bank,
}) => pumpPage(
  tester,
  const CommentBankPage(),
  seed: (db) async {
    final repo = CommentRepository(db);
    for (final s in snippets) {
      await repo.save(s);
    }
  },
);

/// Lets a drift write and the stream re-query it triggers land.
Future<void> _settleDb(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('empty bank explains what it is for', (tester) async {
    await _pump(tester, snippets: const []);
    expect(find.text('No saved comments yet'), findsOneWidget);
    expect(find.text('Add comment'), findsOneWidget);
  });

  testWidgets('lists most-used first and shows use counts', (tester) async {
    await _pump(tester);
    expect(
      _y(tester, 'Cite your sources.'),
      lessThan(_y(tester, 'Strong thesis.')),
    );
    expect(
      _y(tester, 'Strong thesis.'),
      lessThan(_y(tester, 'Proofread before submitting.')),
    );
    expect(find.text('Research · Used 9 times'), findsOneWidget);
    expect(find.text('Never used'), findsOneWidget);
  });

  testWidgets('search and category chips filter the list', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'proof');
    await tester.pumpAndSettle();
    expect(find.text('Proofread before submitting.'), findsOneWidget);
    expect(find.text('Cite your sources.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No comments match “zzz”'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Praise'));
    await tester.pumpAndSettle();
    expect(find.text('Strong thesis.'), findsOneWidget);
    expect(find.text('Cite your sources.'), findsNothing);

    await tester.tap(find.text('Uncategorised'));
    await tester.pumpAndSettle();
    expect(find.text('Proofread before submitting.'), findsOneWidget);
    expect(find.text('Strong thesis.'), findsNothing);
  });

  testWidgets('add a snippet with a category', (tester) async {
    final app = await _pump(tester, snippets: const []);
    await tester.tap(find.text('Add comment'));
    await tester.pumpAndSettle();
    expect(find.text('New comment'), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Vary your sentence length.');
    await tester.enterText(fields.at(1), 'Style');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _settleDb(tester);

    expect(find.text('New comment'), findsNothing);
    final all = await _all(tester, app);
    expect(all.single.text, 'Vary your sentence length.');
    expect(all.single.category, 'Style');
    expect(find.text('Vary your sentence length.'), findsOneWidget);
  });

  testWidgets('tap to edit a snippet', (tester) async {
    final app = await _pump(tester);
    await tester.tap(find.text('Strong thesis.'));
    await tester.pumpAndSettle();
    expect(find.text('Edit comment'), findsOneWidget);
    await tester.enterText(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          )
          .first,
      'Very strong thesis.',
    );
    await tester.tap(find.text('Save'));
    await _settleDb(tester);
    final edited = (await _all(tester, app)).firstWhere((s) => s.id == 'k1');
    expect(edited.text, 'Very strong thesis.');
    expect(edited.useCount, 2, reason: 'editing keeps the use count');
  });

  testWidgets('delete asks first, and can be undone', (tester) async {
    final app = await _pump(tester);
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this comment?'), findsOneWidget);

    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await _all(tester, app), hasLength(3));

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _settleDb(tester);
    expect(await _all(tester, app), hasLength(2));
    expect(find.text('Cite your sources.'), findsNothing);

    await tester.tap(find.text('Undo'));
    await _settleDb(tester);
    final restored = await _all(tester, app);
    expect(restored, hasLength(3));
    expect(restored.firstWhere((s) => s.id == 'k2').useCount, 9);
  });
}
