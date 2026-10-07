import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubrics/builtin_templates.dart';
import 'package:rubric/features/rubrics/rubric_detail_page.dart';
import 'package:rubric/features/rubrics/template_gallery_page.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fixtures.dart';

/// Tall enough to build the whole catalogue.
const tall = Size(390, 12000);

List<String> cardTitles(WidgetTester tester) => tester
    .widgetList<RubricCard>(find.byType(RubricCard))
    .map((c) => c.cardTitleText)
    .toList();

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('shows every built-in template grouped by subject', (
    tester,
  ) async {
    await pumpPage(tester, const TemplateGalleryPage(), size: tall);
    expect(
      cardTitles(tester).toSet(),
      builtinTemplates.map((t) => t.rubric.title).toSet(),
    );
    final subjects = builtinTemplates.map((t) => t.rubric.subject).toSet();
    for (final subject in subjects) {
      expect(find.text(subject.toUpperCase()), findsOneWidget);
    }
    final lab = builtinTemplateById('builtin-lab-report')!;
    expect(
      find.text(
        'Grades 9–12 · ${lab.rubric.objectives.length} objectives · Detailed',
      ),
      findsOneWidget,
    );
  });

  testWidgets('search filters by title, subject or grade band', (tester) async {
    await pumpPage(tester, const TemplateGalleryPage(), size: tall);

    await tester.enterText(find.byType(TextField), 'lab report');
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['Lab Report']);

    await tester.enterText(find.byType(TextField), 'k–2');
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['Reading Response']);

    await tester.enterText(find.byType(TextField), 'underwater basket');
    await tester.pumpAndSettle();
    expect(cardTitles(tester), isEmpty);
    expect(find.text('No templates match'), findsOneWidget);
  });

  testWidgets("lists the teacher's own templates first", (tester) async {
    await pumpPage(
      tester,
      const TemplateGalleryPage(),
      size: tall,
      seed: (db) => RubricRepository(db)
          .save(essayRubric().copyWith(title: 'My Essay', isTemplate: true)),
    );
    expect(find.text('YOUR TEMPLATES'), findsOneWidget);
    expect(cardTitles(tester).first, 'My Essay');
  });

  testWidgets('tapping a template opens its preview', (tester) async {
    final app = await pumpPage(tester, const TemplateGalleryPage());
    final first = find.text(builtinTemplates.first.rubric.title);
    await tester.scrollUntilVisible(
      first,
      300,
      // The page's own scroll view (the first Scrollable), whatever widget
      // builds it: harbor's fairway is a CustomScrollView subclass, which
      // byType(CustomScrollView) does not match.
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(app.visited, ['/rubrics/${builtinTemplates.first.id}']);
  });

  testWidgets('Use This Template copies it into the library and opens review', (
    tester,
  ) async {
    final template = builtinTemplateById('builtin-lab-report')!;
    final app = await pumpPage(tester, RubricDetailPage(rubricId: template.id));
    // The preview is the full read-only rendering.
    expect(find.text('Lab Report'), findsOneWidget);
    expect(find.textContaining('Grades 9–12'), findsOneWidget);

    await tester.tap(find.text('Use This Template'));
    await settle(tester);

    final stored = (await tester.runAsync(
      () => RubricRepository(app.db).all(),
    ))!;
    final copy = stored.single;
    expect(copy.isTemplate, isFalse);
    expect(copy.id, isNot(template.id));
    expect(copy.title, 'Lab Report');
    expect(copy.mode, GradingMode.detailed);
    expect(copy.isReady, isTrue);
    expect(app.visited, ['/build/${copy.id}?step=review']);
  });
}
