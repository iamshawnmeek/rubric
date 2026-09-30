import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/onboarding/first_objective_sheet.dart';
import 'package:rubric/features/onboarding/onboarding_actions.dart';
import 'package:rubric/features/settings/account_section.dart';
import 'package:rubric/l10n/l10n.dart';

/// First run: the big logo fades in on the dark background, a scrim settles
/// over it, then a pager of three purple cards rises from the bottom.
///
/// The last card leads to "Let's create your first rubric." (which opens the
/// builder on a saved draft), or to the demo classroom, or straight Home.
class WelcomePage extends ConsumerStatefulWidget {
  const new({super.key});

  /// Pages never grow wider than this, so tablets keep the phone composition.
  static const maxSheetWidth = 560.0;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

enum _Busy { none, rubric, sample, skip }

class _WelcomePageState extends ConsumerState<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final _logo = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, .4, curve: Curves.easeInOut),
  );
  late final _scrim = CurvedAnimation(
    parent: _intro,
    curve: const Interval(.45, .7, curve: Curves.easeInOut),
  );
  late final _sheet = CurvedAnimation(
    parent: _intro,
    curve: const Interval(.55, 1, curve: Curves.easeOutCubic),
  );
  final _pages = PageController();
  int _page = 0;

  /// Height the bottom sheet occupies, measured after layout. The logo is
  /// centred in the space ABOVE it: v1 pinned it at 30% of the screen, which on
  /// tall phones put it behind the taller v2 card (seen on an iPhone 17 Pro).
  double _sheetHeight = 0;
  _Busy _busy = _Busy.none;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _logo.dispose();
    _scrim.dispose();
    _sheet.dispose();
    _intro.dispose();
    _pages.dispose();
    super.dispose();
  }

  bool get _isLast => _page == 2;

  void _goToPage(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _run(_Busy kind, Future<void> Function() action) async {
    if (_busy != _Busy.none) return;
    setState(() => _busy = kind);
    try {
      await action();
    } on Object {
      if (mounted) showRubricSnack(context, context.l10n.welcomeActionError);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  Future<void> _createFirstRubric() async {
    final l = context.l10n;
    final objective = await showFirstObjectiveSheet(context);
    if (objective == null || !mounted) return;
    await _run(_Busy.rubric, () async {
      final id = await ref.saveFirstRubric(objective, l.rubricStateTitleOne);
      if (mounted) context.go(Routes.buildRubric(id, firstRun: true));
    });
  }

  Future<void> _exploreSample() => _run(_Busy.sample, () async {
    await ref.exploreSampleData();
    if (mounted) context.go(Routes.home);
  });

  /// A teacher with an account already (a second device): sign in, and
  /// their classes arrive by sync, so there is nothing to set up here.
  Future<void> _signIn() async {
    await showRubricSheet<void>(context: context, child: const AccountSheet());
    if (!mounted) return;
    if (ref.read(syncServiceProvider)?.state.signedIn ?? false) await _skip();
  }

  Future<void> _skip() => _run(_Busy.skip, () async {
    await ref.completeOnboarding();
    if (mounted) context.go(Routes.home);
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pages = [
      (l.onboarding1Title, l.onboarding1Message),
      (l.onboarding2Title, l.onboarding2Message),
      (l.onboarding3Title, l.onboarding3Message),
    ];

    return Scaffold(
      backgroundColor: secondary,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: _sheetHeight,
            child: SafeArea(
              bottom: false,
              child: FadeTransition(
                opacity: _logo,
                child: const Center(
                  child: FittedBox(fit: BoxFit.scaleDown, child: RubricLogo()),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _scrim,
                child: ColoredBox(color: Colors.black.withValues(alpha: .4)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: _sheet,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .35),
                  end: Offset.zero,
                ).animate(_sheet),
                child: _MeasureHeight(
                  onChange: (h) {
                    if (h != _sheetHeight) setState(() => _sheetHeight = h);
                  },
                  child: SafeArea(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: WelcomePage.maxSheetWidth,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Pager(
                              controller: _pages,
                              pages: pages,
                              onPageChanged: (page) =>
                                  setState(() => _page = page),
                            ),
                            _Footer(
                              page: _page,
                              count: pages.length,
                              busy: _busy == _Busy.rubric,
                              onSkip: () => _goToPage(pages.length - 1),
                              onNext: _isLast
                                  ? _createFirstRubric
                                  : () => _goToPage(_page + 1),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              child: _isLast
                                  ? _Alternatives(
                                      busy: _busy,
                                      onSample: _exploreSample,
                                      onSkip: _skip,
                                      onSignIn:
                                          ref.watch(syncServiceProvider) == null
                                          ? null
                                          : _signIn,
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three purple cards. A [PageView] needs a fixed height, so an invisible
/// stack of every card sizes the pager to the tallest one.
class _Pager extends StatelessWidget {
  const new({
    required this.controller,
    required this.pages,
    required this.onPageChanged,
  });

  final PageController controller;
  final List<(String, String)> pages;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final (title, message) in pages)
        _WelcomeCard(title: title, message: message),
    ];
    return Stack(
      children: [
        ExcludeSemantics(
          child: Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: IndexedStack(children: cards),
          ),
        ),
        Positioned.fill(
          child: PageView(
            controller: controller,
            onPageChanged: onPageChanged,
            children: cards,
          ),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const new({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Insets.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.xl,
      ),
      decoration: BoxDecoration(borderRadius: Corners.card, color: primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(header: true, child: BodyHeadline(title)),
          const SizedBox(height: 42),
          Text(message, style: RubricTextStyles.pageInfo),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const new({
    required this.page,
    required this.count,
    required this.busy,
    required this.onSkip,
    required this.onNext,
  });

  final int page;
  final int count;
  final bool busy;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isLast = page == count - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(45, Insets.sm, Insets.sm, Insets.sm),
      child: Row(
        children: [
          _Dots(page: page, count: count),
          const SizedBox(width: Insets.sm),
          // Wraps rather than overflows at large text sizes.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                if (!isLast) _PagerButton(label: l.skipTitle, onTap: onSkip),
                _PagerButton(label: l.nextTitle, onTap: busy ? null : onNext),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Page dots: the current one is a wider primaryLight pill, the rest accent
/// circles, so position reads by shape as well as colour.
class _Dots extends StatelessWidget {
  const new({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.welcomePageIndicator(page + 1, count),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              width: i == page ? 22 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: i == page ? primaryLight : accent,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
        ],
      ),
    );
  }
}

/// The v1 pager button: accent fill, secondary-coloured label, 10pt radius.
class _PagerButton extends StatelessWidget {
  const new({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: accent,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.minTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              child: Text(label, style: RubricTextStyles.button),
            ),
          ),
        ),
      ),
    );
  }
}

/// On the last card: the ways past building a rubric right now.
class _Alternatives extends StatelessWidget {
  const new({
    required this.busy,
    required this.onSample,
    required this.onSkip,
    this.onSignIn,
  });

  final _Busy busy;
  final VoidCallback onSample;
  final VoidCallback onSkip;

  /// Null when sync isn't set up (tests, or no server configured).
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final idle = busy == _Busy.none;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Insets.sm,
        children: [
          TextButton(
            onPressed: idle ? onSample : null,
            child: busy == _Busy.sample
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : Text(l.welcomeSampleData),
          ),
          TextButton(
            onPressed: idle ? onSkip : null,
            child: Text(l.welcomeSkipForNow),
          ),
          if (onSignIn != null)
            TextButton(
              key: const Key('welcome.signIn'),
              onPressed: idle ? onSignIn : null,
              child: Text(l.welcomeHaveAccount),
            ),
        ],
      ),
    );
  }
}

/// Reports its child's laid-out height after each layout in which it changed.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const new({required this.onChange, required super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) => renderObject.onChange = onChange;
}

class _RenderMeasureHeight extends RenderProxyBox {
  new(this.onChange);

  ValueChanged<double> onChange;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    // Reporting during layout would setState mid-frame; defer to after it.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(height));
  }
}
