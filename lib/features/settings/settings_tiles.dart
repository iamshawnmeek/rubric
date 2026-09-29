import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';

/// Widest the settings column grows; beyond it a tablet shows margins rather
/// than stretched cards.
const settingsMaxWidth = 720.0;

/// Centres [children] and caps its width at [settingsMaxWidth].
class SettingsColumn extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: settingsMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A section: a [SectionLabel] over cards spaced 12pt apart.
class SettingsSection extends StatelessWidget {
  const new({required this.label, required this.children, super.key});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label),
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: Insets.sm),
          child,
        ],
      ],
    );
  }
}

/// A tappable card row that opens something: hint over title, chevron right.
class SettingsLinkTile extends StatelessWidget {
  const new({
    required this.hint,
    required this.title,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final String hint;
  final String title;
  final VoidCallback? onTap;

  /// Replaces the chevron (e.g. a spinner while the action runs).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.minTap),
      child: RubricCard(
        cardHintText: hint,
        cardTitleText: title,
        onTap: onTap,
        trailing:
            trailing ??
            const FaIcon(
              FontAwesomeIcons.chevronRight,
              color: primaryLightest,
              size: 18,
            ),
      ),
    );
  }
}

/// A card row with an on/off switch; the whole card toggles it.
class SettingsSwitchTile extends StatelessWidget {
  const new({
    required this.hint,
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String hint;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: '$hint, $title',
      onTap: () => onChanged(!value),
      excludeSemantics: true,
      child: Material(
        color: primaryCard,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: () => onChanged(!value),
          child: Padding(
            padding: Insets.card,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CardHint(hint),
                      const SizedBox(height: Insets.xs),
                      CardTitle(title),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card holding an inline control (a toggle, a stepper) under its hint.
class SettingsPanel extends StatelessWidget {
  const new({required this.hint, required this.child, this.footer, super.key});

  final String hint;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Insets.card,
      decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint(hint),
          const SizedBox(height: Insets.sm),
          child,
          if (footer != null) ...[
            const SizedBox(height: Insets.sm),
            Text(footer!, style: RubricTextStyles.caption),
          ],
        ],
      ),
    );
  }
}

/// A round 48pt − / + button on a primaryDark disc.
class SettingsRoundButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final FaIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? .4 : 1,
        child: Material(
          color: primaryDark,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: Sizes.minTap,
              child: Center(
                child: FaIcon(icon, color: primaryLighter, size: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
