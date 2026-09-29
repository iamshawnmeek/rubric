import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';
import 'package:rubric/features/rubric_builder/rubric_draft_notifier.dart';
import 'package:rubric/features/rubric_builder/widgets/builder_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

/// Step 3: stacked regions whose height is their weight, with drag handles
/// between them (v1 "Assign Weights").
class WeightsStep extends ConsumerWidget {
  const new({
    required this.draft,
    required this.rubricId,
    required this.onEditGroups,
    super.key,
  });

  final RubricDraft draft;
  final String rubricId;
  final VoidCallback onEditGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final groups = draft.rubric.groups;
    if (groups.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          title: l.builderWeightsEmptyTitle,
          message: l.builderWeightsEmptyMessage,
          action: FilledButton(
            onPressed: onEditGroups,
            child: Text(l.builderWeightsEmptyAction),
          ),
        ),
      );
    }
    final notifier = ref.read(rubricDraftProvider(rubricId).notifier);

    return SliverList.list(
      children: [
        StepIntro(
          groups.length == 1 ? l.builderWeightsSingle : l.builderWeightsIntro,
        ),
        if (groups.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Insets.lg),
              child: OutlinedButton.icon(
                icon: const FaIcon(FontAwesomeIcons.scaleBalanced, size: 16),
                label: Text(l.builderEvenSplit),
                onPressed: notifier.evenSplit,
              ),
            ),
          ),
        _WeightStack(draft: draft, rubricId: rubricId),
      ],
    );
  }
}

class _WeightStack extends ConsumerStatefulWidget {
  const new({required this.draft, required this.rubricId});

  final RubricDraft draft;
  final String rubricId;

  @override
  ConsumerState<_WeightStack> createState() => _WeightStackState();
}

class _WeightStackState extends ConsumerState<_WeightStack> {
  static const double _handleHeight = Sizes.minTap;
  static const double _minRegion = 68;

  /// Drag distance not yet turned into a whole point.
  double _carry = 0;

  RubricDraftNotifier get _notifier =>
      ref.read(rubricDraftProvider(widget.rubricId).notifier);

  void _drag(int boundary, double dy, double pixelsPerPoint) {
    _carry += dy / pixelsPerPoint;
    final whole = _carry.truncate();
    if (whole == 0) return;
    _carry -= whole;
    final before = widget.draft.rubric.groups[boundary].weight;
    _notifier.moveBoundary(boundary, whole);
    final after = ref
        .read(rubricDraftProvider(widget.rubricId))
        .value
        ?.rubric
        .groups[boundary]
        .weight;
    if (after != before && ref.read(settingsProvider).haptics) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final groups = widget.draft.rubric.groups;
    final handles = groups.length - 1;
    // The stack fills most of a phone screen; the regions share what the
    // handles leave, in proportion to their weight.
    final available = math.max(
      MediaQuery.sizeOf(context).height * .55,
      groups.length * _minRegion + handles * _handleHeight,
    );
    final regionSpace = available - handles * _handleHeight;
    final pixelsPerPoint = regionSpace / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          _Region(
            group: groups[i],
            height: math.max(_minRegion, pixelsPerPoint * groups[i].weight),
            locked: widget.draft.locked.contains(groups[i].id),
            canEdit: groups.length > 1,
            onLock: () => _notifier.toggleLock(groups[i].id),
            onSetWeight: () => _promptWeight(groups[i]),
          ),
          if (i < handles)
            _Handle(
              key: ValueKey('weight-handle-$i'),
              label: l.builderBoundarySemantics(
                groups[i].title,
                groups[i + 1].title,
              ),
              value: l.builderPercent(groups[i].weight),
              increasedValue: l.builderPercent(groups[i].weight + 1),
              decreasedValue: l.builderPercent(groups[i].weight - 1),
              onDragStart: () => _carry = 0,
              onDrag: (dy) => _drag(i, dy, pixelsPerPoint),
              onIncrease: () => _notifier.moveBoundary(i, 1),
              onDecrease: () => _notifier.moveBoundary(i, -1),
            ),
        ],
      ],
    );
  }

  Future<void> _promptWeight(RubricGroup group) async {
    final value = await showRubricSheet<int>(
      context: context,
      child: _WeightSheet(group: group),
    );
    if (value != null) _notifier.setWeight(group.id, value);
  }
}

class _Region extends StatelessWidget {
  const new({
    required this.group,
    required this.height,
    required this.locked,
    required this.canEdit,
    required this.onLock,
    required this.onSetWeight,
  });

  final RubricGroup group;
  final double height;
  final bool locked;
  final bool canEdit;
  final VoidCallback onLock;
  final VoidCallback onSetWeight;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final percent = l.builderPercent(group.weight);
    // v1 switched to one line under 18%; short regions need it too, or the
    // big percentage would not fit.
    final compact = group.weight <= 18 || height < 120;
    final lock = canEdit
        ? RubricLock(isActive: locked, onTap: onLock)
        : const SizedBox.shrink();
    final title = group.title.trim().isEmpty
        ? l.builderUntitledGroup
        : group.title;

    return Semantics(
      container: true,
      label: l.builderWeightSemantics(title, group.weight),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: height,
        decoration: BoxDecoration(borderRadius: Corners.card, color: primary),
        child: compact
            ? Padding(
                padding: const EdgeInsets.only(left: 22, right: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: _Tappable(
                        label: l.builderSetWeightTitle(title),
                        onTap: canEdit ? onSetWeight : null,
                        child: BodyOne(
                          '$percent: $title',
                          fontSize: 21,
                          color: primaryLighter,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    lock,
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                child: Stack(
                  children: [
                    BodyOne(
                      title,
                      fontSize: 21,
                      color: primaryLighter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 54),
                          _Tappable(
                            label: l.builderSetWeightTitle(title),
                            onTap: canEdit ? onSetWeight : null,
                            child: BodyOneWeights(percent),
                          ),
                          const SizedBox(width: 10),
                          lock,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Tappable extends StatelessWidget {
  const new({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: onTap == null ? null : label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTap),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The pill between two regions. Dragging it down grows the region above.
class _Handle extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.increasedValue,
    required this.decreasedValue,
    required this.onDragStart,
    required this.onDrag,
    required this.onIncrease,
    required this.onDecrease,
    super.key,
  });

  final String label;
  final String value;
  final String increasedValue;
  final String decreasedValue;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      slider: true,
      label: label,
      value: value,
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => onDragStart(),
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        child: SizedBox(
          height: _WeightStackState._handleHeight,
          child: Center(
            child: Container(
              height: 10,
              width: 80,
              decoration: BoxDecoration(
                borderRadius: Corners.card,
                color: primaryLighter,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Type an exact weight for one group.
class _WeightSheet extends StatefulWidget {
  const new({required this.group});

  final RubricGroup group;

  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  late final _controller = TextEditingController(
    text: '${widget.group.weight}',
  );

  int? get _value {
    final v = int.tryParse(_controller.text);
    return v == null || v < 1 || v > 99 ? null : v;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_value != null) Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final title = widget.group.title.trim().isEmpty
        ? l.builderUntitledGroup
        : widget.group.title;
    return RubricSheet(
      title: l.builderSetWeightTitle(title),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RubricFormWell(
            child: Row(
              children: [
                Expanded(
                  child: RubricTextField(
                    controller: _controller,
                    hintText: l.builderSetWeightHint,
                    semanticLabel: l.builderSetWeightHint,
                    autofocus: true,
                    style: RubricTextStyles.bodyWeights,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const BodyOneWeights('%', color: primaryLighter),
              ],
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(l.builderSetWeightHelp, style: RubricTextStyles.caption),
          const SizedBox(height: Insets.lg),
          AccentButton(
            label: l.builderSetWeightAction,
            onTap: _value == null ? null : _submit,
            widthFactor: .15,
          ),
        ],
      ),
    );
  }
}
