import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';
import 'package:rubric/features/rubric_builder/rubric_draft_notifier.dart';
import 'package:rubric/features/rubric_builder/steps/groups_step.dart';
import 'package:rubric/features/rubric_builder/steps/objectives_step.dart';
import 'package:rubric/features/rubric_builder/steps/review_step.dart';
import 'package:rubric/features/rubric_builder/steps/scale_step.dart';
import 'package:rubric/features/rubric_builder/steps/weights_step.dart';
import 'package:rubric/features/rubric_builder/widgets/builder_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

/// The steps of building a rubric, in order. The v1 onboarding screens
/// (objectives → groups → weights → grading scale) become these steps.
enum BuilderStep { objectives, groups, weights, scale, review }

/// Builds a new rubric or edits an existing one, one step per screen.
///
/// Opening an existing rubric at [step] other than objectives edits just that
/// part: back leaves the builder and, once the rubric is valid, the button
/// saves instead of moving on. Existing rubrics are autosaved whenever the
/// step changes (if they are valid); new ones are saved from Review.
class RubricBuilderPage extends ConsumerStatefulWidget {
  const new({
    required this.rubricId,
    this.step = BuilderStep.objectives,
    this.firstRun = false,
    super.key,
  });

  /// `new` creates a fresh rubric; anything else edits that rubric.
  final String rubricId;
  final BuilderStep step;

  /// True when reached from first-run onboarding: finishing marks onboarding
  /// complete and lands on Home.
  final bool firstRun;

  @override
  ConsumerState<RubricBuilderPage> createState() => _RubricBuilderPageState();
}

class _RubricBuilderPageState extends ConsumerState<RubricBuilderPage> {
  /// Where the teacher came in; backing out of it leaves the builder.
  late BuilderStep _entry;
  late BuilderStep _step;
  bool _started = false;
  bool _saving = false;
  final _titleFocus = FocusNode();

  AsyncNotifierProvider<RubricDraftNotifier, RubricDraft?> get _provider =>
      rubricDraftProvider(widget.rubricId);

  RubricDraftNotifier get _notifier => ref.read(_provider.notifier);

  RubricDraft? get _draft => ref.read(_provider).value;

  /// Editing one part of an existing rubric, reached by deep link.
  bool get _focused => _entry != BuilderStep.objectives;

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  /// Settles the first step once the draft has loaded: a brand-new rubric
  /// always starts with its objectives.
  void _start(RubricDraft draft) {
    if (_started) return;
    _started = true;
    _entry = draft.isNew ? BuilderStep.objectives : widget.step;
    _step = _entry;
  }

  Future<void> _goTo(BuilderStep step) async {
    FocusScope.of(context).unfocus();
    await _autosave();
    if (mounted) setState(() => _step = step);
  }

  /// Existing rubrics are kept up to date as the teacher moves between steps
  /// — but only when valid, so a half-made change never reaches grading.
  Future<void> _autosave() async {
    final draft = _draft;
    if (draft == null || draft.isNew || !draft.isDirty || !draft.isComplete) {
      return;
    }
    try {
      await _notifier.save();
    } on Object {
      if (mounted) showRubricSnack(context, context.l10n.builderSaveFailed);
    }
  }

  Future<void> _back() async {
    if (_step != _entry && _step.index > 0) {
      await _goTo(BuilderStep.values[_step.index - 1]);
      return;
    }
    final draft = _draft;
    if (draft != null && draft.isDirty) {
      final l = context.l10n;
      final discard = await confirm(
        context,
        title: l.builderDiscardTitle,
        message: l.builderDiscardMessage,
        confirmLabel: l.builderDiscardConfirm,
        cancelLabel: l.builderKeepEditing,
      );
      if (!discard || !mounted) return;
    }
    _leave(draft);
  }

  void _leave(RubricDraft? draft) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else if (widget.firstRun) {
      router.go(Routes.welcome);
    } else if (draft != null && !draft.isNew) {
      router.go(Routes.rubric(draft.rubric.id));
    } else {
      router.go(Routes.rubrics);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final l = context.l10n;
    final router = GoRouter.of(context);
    try {
      final saved = await _notifier.save();
      if (widget.firstRun) {
        await ref
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(onboardingComplete: true));
      }
      if (!mounted) return;
      showRubricSnack(context, l.builderSaved);
      router.go(widget.firstRun ? Routes.home : Routes.rubric(saved.id));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showRubricSnack(context, l.builderSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(_provider);

    final page = switch (state) {
      AsyncData(value: final RubricDraft draft) => _buildStep(draft),
      AsyncData() => RubricPage(
        title: l.builderMissingTitle,
        showBack: true,
        onBack: () => _leave(null),
        children: [
          EmptyState(
            title: l.builderMissingTitle,
            message: l.builderMissingMessage,
            action: FilledButton(
              onPressed: () => GoRouter.of(context).go(Routes.rubrics),
              child: Text(l.builderMissingAction),
            ),
          ),
        ],
      ),
      AsyncError(:final error) => RubricPage(
        title: l.builderTitle,
        showBack: true,
        onBack: () => _leave(null),
        children: [EmptyState(title: l.builderLoadFailed, message: '$error')],
      ),
      _ => RubricPage(
        title: l.builderTitle,
        showBack: true,
        onBack: () => _leave(null),
        children: const [
          Padding(
            padding: EdgeInsets.all(Insets.xl),
            child: Center(child: CircularProgressIndicator(color: accent)),
          ),
        ],
      ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      // Tablets: keep the builder a readable column instead of stretching.
      child: ColoredBox(
        color: secondary,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: builderMaxWidth),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: KeyedSubtree(
                key: ValueKey(state.value == null ? state.runtimeType : _step),
                child: page,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(RubricDraft draft) {
    _start(draft);
    final l = context.l10n;
    final step = _step;
    final steps = BuilderStep.values.length;

    final Widget content = switch (step) {
      BuilderStep.objectives => ObjectivesStep(
        draft: draft,
        rubricId: widget.rubricId,
      ),
      BuilderStep.groups => GroupsStep(
        draft: draft,
        rubricId: widget.rubricId,
        onEditObjectives: () => _goTo(BuilderStep.objectives),
      ),
      BuilderStep.weights => WeightsStep(
        draft: draft,
        rubricId: widget.rubricId,
        onEditGroups: () => _goTo(BuilderStep.groups),
      ),
      BuilderStep.scale => ScaleStep(draft: draft, rubricId: widget.rubricId),
      BuilderStep.review => ReviewStep(
        draft: draft,
        rubricId: widget.rubricId,
        titleFocus: _titleFocus,
        onFix: _goTo,
      ),
    };

    return RubricPage(
      title: _titleOf(step, l),
      subtitle: l.builderStepProgress(step.index + 1, steps),
      showBack: true,
      onBack: _back,
      bottomCta: _cta(draft),
      slivers: [
        SliverPadding(
          padding: Insets.page,
          sliver: SliverList.list(
            children: [
              Semantics(
                label: l.builderStepProgress(step.index + 1, steps),
                excludeSemantics: true,
                child: RubricProgressBar(value: (step.index + 1) / steps),
              ),
              const SizedBox(height: Insets.xl),
            ],
          ),
        ),
        SliverPadding(padding: Insets.page, sliver: content),
      ],
    );
  }

  /// The docked call to action for the current step.
  Widget _cta(RubricDraft draft) {
    final l = context.l10n;
    final saveOnly =
        _step == BuilderStep.review ||
        (_focused && !draft.isNew && draft.isComplete);
    if (saveOnly) {
      return AccentButton(
        label: _step == BuilderStep.review
            ? l.builderSaveLabel
            : l.builderSaveChangesLabel,
        onTap: draft.isComplete && !_saving ? _save : null,
      );
    }
    final next = BuilderStep.values[_step.index + 1];
    return switch (_step) {
      BuilderStep.objectives => NextButton(
        onTap: draft.objectives.isEmpty ? null : () => _goTo(next),
      ),
      BuilderStep.groups when draft.ungrouped.isNotEmpty => UngroupedTray(
        draft: draft,
        rubricId: widget.rubricId,
      ),
      BuilderStep.groups => NextButton(
        onTap: draft.rubric.groups.every((g) => g.title.trim().isNotEmpty)
            ? () => _goTo(next)
            : null,
      ),
      BuilderStep.weights => NextButton(
        onTap: draft.rubric.groups.isEmpty ? null : () => _goTo(next),
      ),
      _ => SetGradingScaleButton(
        onTap:
            draft.sortedScale.problem == null &&
                !draft.rubric.issues.contains(RubricIssue.noLevels) &&
                !draft.rubric.issues.contains(RubricIssue.duplicateLevelPoints)
            ? () => _goTo(next)
            : null,
      ),
    };
  }

  static String _titleOf(BuilderStep step, AppLocalizations l) =>
      switch (step) {
        BuilderStep.objectives => l.builderStepObjectivesTitle,
        BuilderStep.groups => l.assignGroupsHeadline,
        BuilderStep.weights => l.builderStepWeightsTitle,
        BuilderStep.scale => l.gradingScaleTitle,
        BuilderStep.review => l.builderStepReviewTitle,
      };
}
