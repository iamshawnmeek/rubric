import 'package:flutter/material.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/text_styles.dart';

/// The Simple/Detailed style toggle: the selected segment sits on a
/// primaryDark pill, the others fade to primaryLighter.
class SegmentedToggle<T> extends StatelessWidget {
  const new({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in segments.entries)
          Expanded(
            child: Semantics(
              button: true,
              selected: entry.key == selected,
              label: entry.value,
              onTap: () => onChanged(entry.key),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: Corners.card,
                    color: entry.key == selected ? primaryDark : null,
                  ),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: RubricTextStyles.toggleActive.copyWith(
                        color: entry.key == selected ? white : primaryLighter,
                      ),
                      child: FittedBox(child: Text(entry.value)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
