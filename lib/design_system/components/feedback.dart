import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/components/rubric_logo.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/text_styles.dart';

/// Shown in place of an empty list: a faint logo mark, a line of copy and an
/// optional action.
class EmptyState extends StatelessWidget {
  const new({required this.title, this.message, this.action, super.key});

  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xl),
      child: Column(
        children: [
          const Opacity(
            opacity: .35,
            child: RubricLogo(width: 140, height: 42),
          ),
          const SizedBox(height: Insets.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: RubricTextStyles.cardTitle,
          ),
          if (message != null) ...[
            const SizedBox(height: Insets.sm),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: RubricTextStyles.bodySmall,
            ),
          ],
          if (action != null) ...[const SizedBox(height: Insets.lg), action!],
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const new(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text.toUpperCase(),
                style: RubricTextStyles.sectionLabel,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A compact metric: big white number, small purple label.
class StatTile extends StatelessWidget {
  const new({
    required this.value,
    required this.label,
    this.color = primaryCard,
    this.valueColor = white,
    super.key,
  });

  final String value;
  final String label;
  final Color color;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: color, borderRadius: Corners.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              child: Text(
                value,
                style: RubricTextStyles.statValue.copyWith(color: valueColor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RubricTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded pill label; [selected] fills it with the accent.
class RubricChip extends StatelessWidget {
  const new({
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? secondary : primaryLighter;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? accent : primaryDark,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: RubricTextStyles.caption.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin rounded progress bar in palette colors. [value] is 0–1.
class RubricProgressBar extends StatelessWidget {
  const new({
    required this.value,
    this.height = 8,
    this.color = accent,
    this.track = primaryDark,
    super.key,
  });

  final double value;
  final double height;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        color: color,
        backgroundColor: track,
      ),
    );
  }
}

/// Renders an [AsyncValue] with on-brand loading and error states.
class AsyncView<T> extends StatelessWidget {
  const new({required this.value, required this.data, super.key});

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const Padding(
        padding: EdgeInsets.all(Insets.xl),
        child: Center(child: CircularProgressIndicator(color: accent)),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Text(
          'Something went wrong.\n$error',
          style: RubricTextStyles.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Sliver form of [AsyncView].
class SliverAsyncView<T> extends StatelessWidget {
  const new({required this.value, required this.data, super.key});

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(Insets.xl),
          child: Center(child: CircularProgressIndicator(color: accent)),
        ),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Text(
            'Something went wrong.\n$error',
            style: RubricTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

void showRubricSnack(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// A confirm dialog in the house style. Resolves true when confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancelLabel ?? MaterialLocalizations.of(context).cancelButtonLabel,
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
