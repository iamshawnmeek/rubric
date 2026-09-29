import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';

/// Keeps a page from stretching on tablets: content is centred and capped at
/// [maxWidth], with the page background filling the margins.
class ContentWidth extends StatelessWidget {
  const new({required this.child, this.maxWidth = 720, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: secondary,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// A round badge with a student's initials.
class InitialsAvatar extends StatelessWidget {
  const new(this.initials, {this.size = 44, this.faded = false, super.key});

  final String initials;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: faded ? secondary : primaryDark,
          border: faded ? Border.all(color: inactive) : null,
        ),
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: RubricTextStyles.button.copyWith(
            color: faded ? inactive : white,
            fontFamily: Fonts.black,
          ),
        ),
      ),
    );
  }
}

/// One row of an [showActionSheet].
class SheetAction<T> {
  const new({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final FaIconData icon;

  /// Drawn in the accent so a destructive choice stands out (the label names
  /// it too — color is never the only signal).
  final bool destructive;
}

/// A [RubricSheet] listing [actions]; resolves to the chosen value.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<SheetAction<T>> actions,
}) {
  return showRubricSheet<T>(
    context: context,
    child: RubricSheet(
      title: title,
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in actions)
            Builder(
              builder: (context) {
                final color = action.destructive ? accent : white;
                return Semantics(
                  button: true,
                  label: action.label,
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: Corners.card,
                    onTap: () => Navigator.of(context).pop(action.value),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: FaIcon(action.icon, color: color, size: 18),
                          ),
                          Expanded(
                            child: Text(
                              action.label,
                              style: RubricTextStyles.listTitle.copyWith(
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}

/// A labelled input in a sheet: a CardHint label over a RubricTextField.
class LabeledField extends StatelessWidget {
  const new({
    required this.label,
    required this.hint,
    required this.controller,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.words,
    this.onSubmitted,
    this.onChanged,
    super.key,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint(label, fontSize: 14),
          const SizedBox(height: 4),
          RubricTextField(
            controller: controller,
            hintText: hint,
            semanticLabel: label,
            autofocus: autofocus,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            style: RubricTextStyles.bodyPlaceholder.copyWith(fontSize: 22),
            hintStyle: RubricTextStyles.bodyPlaceholder.copyWith(
              fontSize: 22,
              color: inactive,
            ),
          ),
        ],
      ),
    );
  }
}

/// A 48pt-tall accent-outlined pill for secondary actions in a toolbar row.
class PillAction extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final FaIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: primaryDark,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.minTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(icon, size: 14, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: RubricTextStyles.caption.copyWith(color: white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
