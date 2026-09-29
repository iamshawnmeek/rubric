import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/components/small_logo.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/headline_one.dart';

/// The standard page layout: small logo (or back chevron), a HeadlineOne
/// title, then scrolling content, with an optional docked CTA.
///
/// Pass [slivers] for long/lazy lists; otherwise [children] are laid out in a
/// padded column.
class RubricPage extends StatelessWidget {
  const new({
    required this.title,
    this.children = const [],
    this.slivers,
    this.actions = const [],
    this.showBack,
    this.showLogo = true,
    this.bottomCta,
    this.floatingActionButton,
    this.subtitle,
    this.onBack,
    this.controller,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? slivers;
  final List<Widget> actions;

  /// Defaults to "can this route pop".
  final bool? showBack;
  final bool showLogo;
  final VoidCallback? onBack;
  final Widget? bottomCta;
  final Widget? floatingActionButton;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? GoRouter.of(context).canPop();
    final header = SliverPadding(
      padding: Insets.page.copyWith(top: Insets.pageTop),
      sliver: SliverList.list(
        children: [
          Row(
            children: [
              if (canPop)
                BackChevron(onTap: onBack ?? () => context.pop())
              else if (showLogo)
                const Expanded(child: SmallLogo()),
              if (canPop || !showLogo) const Spacer(),
              ...actions,
            ],
          ),
          SizedBox(height: canPop ? Insets.lg : 60),
          Semantics(header: true, child: HeadlineOne(title)),
          if (subtitle != null) ...[
            const SizedBox(height: Insets.xs),
            Text(
              subtitle!,
              style: const TextStyle(
                fontFamily: 'Avenir-Heavy',
                fontSize: 18,
                color: primaryLight,
              ),
            ),
          ],
          const SizedBox(height: Insets.xl),
        ],
      ),
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        floatingActionButton: bottomCta ?? floatingActionButton,
        floatingActionButtonLocation: bottomCta != null
            ? FloatingActionButtonLocation.centerDocked
            : FloatingActionButtonLocation.endFloat,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: controller,
            slivers: [
              header,
              if (slivers != null)
                ...slivers!
              else
                SliverPadding(
                  padding: Insets.page,
                  sliver: SliverList.list(children: children),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: bottomCta != null ? 130 : 96),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BackChevron extends StatelessWidget {
  const new({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox(
          height: 52,
          width: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FaIcon(FontAwesomeIcons.chevronLeft, color: primaryLightest),
          ),
        ),
      ),
    );
  }
}

/// A round icon action in the page header row.
class HeaderAction extends StatelessWidget {
  const new({
    required this.icon,
    required this.onTap,
    required this.label,
    super.key,
  });

  final FaIconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: FaIcon(icon, color: primaryLightest, size: 20),
    );
  }
}
