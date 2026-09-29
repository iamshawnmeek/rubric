import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/sample_data.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/settings/app_info.dart';
import 'package:rubric/features/settings/erase_all_data.dart';
import 'package:rubric/features/settings/grading_scale_editor.dart';
import 'package:rubric/features/settings/scale_draft.dart';
import 'package:rubric/features/settings/settings_tiles.dart';
import 'package:rubric/l10n/l10n.dart';

/// The Settings tab: profile, grading defaults, feedback, data and app.
class SettingsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _loadingSample = false;
  bool _erasing = false;

  Future<void> _update(AppSettings Function(AppSettings) change) =>
      ref.read(settingsProvider.notifier).update(change);

  Future<void> _editName(String current) async {
    final name = await showRubricSheet<String>(
      context: context,
      child: _TeacherNameSheet(initial: current),
    );
    if (name == null || name == current) return;
    await _update((s) => s.copyWith(teacherName: name));
  }

  Future<void> _editScale(GradingScale current) async {
    final scale = await showGradingScaleEditor(context, current);
    if (scale == null || scale == current || !mounted) return;
    await _update((s) => s.copyWith(defaultScale: scale));
    if (!mounted) return;
    final l = context.l10n;
    showRubricSnack(
      context,
      l.settingsScaleUpdated,
      action: SnackBarAction(
        label: l.settingsUndo,
        onPressed: () {
          if (!mounted) return;
          unawaited(_update((s) => s.copyWith(defaultScale: current)));
        },
      ),
    );
  }

  Future<void> _loadSample() async {
    final l = context.l10n;
    setState(() => _loadingSample = true);
    try {
      await loadSampleData(ref.read(databaseProvider));
      if (mounted) showRubricSnack(context, l.settingsSampleLoaded);
    } on Object {
      if (mounted) showRubricSnack(context, l.settingsSampleFailed);
    } finally {
      if (mounted) setState(() => _loadingSample = false);
    }
  }

  Future<void> _eraseAll() async {
    final l = context.l10n;
    final sure = await confirm(
      context,
      title: l.settingsEraseConfirmTitle,
      message: l.settingsEraseConfirmMessage,
      confirmLabel: l.settingsEraseConfirmAction,
    );
    if (!sure || !mounted) return;
    final reallySure = await confirm(
      context,
      title: l.settingsEraseFinalTitle,
      message: l.settingsEraseFinalMessage,
      confirmLabel: l.settingsEraseFinalAction,
    );
    if (!reallySure || !mounted) return;

    setState(() => _erasing = true);
    try {
      await eraseAllData(ref.read(databaseProvider));
    } on Object {
      if (mounted) {
        setState(() => _erasing = false);
        showRubricSnack(context, l.settingsEraseFailed);
      }
      return;
    }
    // Settings last: resetting them ends onboarding, and the router leaves this
    // page for the welcome flow.
    await _update((_) => const AppSettings());
    if (mounted) context.go(Routes.welcome);
  }

  Future<void> _replayOnboarding() async {
    await _update((s) => s.copyWith(onboardingComplete: false));
    if (mounted) context.go(Routes.welcome);
  }

  Future<void> _setHaptics(bool on) async {
    await _update((s) => s.copyWith(haptics: on));
    // A taste of what was just switched on.
    if (on) unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);

    return RubricPage(
      title: l.settingsTitle,
      children: [
        SettingsColumn(
          children: [
            SettingsSection(
              label: l.settingsSectionProfile,
              children: [
                SettingsLinkTile(
                  hint: l.settingsTeacherNameHint,
                  title: settings.teacherName.isEmpty
                      ? l.settingsTeacherNameEmpty
                      : settings.teacherName,
                  onTap: () => _editName(settings.teacherName),
                  trailing: const FaIcon(
                    FontAwesomeIcons.pen,
                    color: primaryLightest,
                    size: 16,
                  ),
                ),
              ],
            ),
            SettingsSection(
              label: l.settingsSectionGrading,
              children: [
                SettingsPanel(
                  hint: l.settingsDefaultModeHint,
                  child: SegmentedToggle<GradingMode>(
                    segments: {
                      GradingMode.simple: l.settingsModeSimple,
                      GradingMode.detailed: l.settingsModeDetailed,
                    },
                    selected: settings.defaultMode,
                    onChanged: (mode) =>
                        _update((s) => s.copyWith(defaultMode: mode)),
                  ),
                ),
                SettingsLinkTile(
                  hint: l.settingsDefaultScaleHint,
                  title: _scaleName(l, settings.defaultScale),
                  onTap: () => _editScale(settings.defaultScale),
                ),
                SettingsPanel(
                  hint: l.settingsDecimalsHint,
                  footer: l.settingsDecimalsExample(
                    '${87.456.toStringAsFixed(settings.decimals)}%',
                  ),
                  child: SegmentedToggle<int>(
                    segments: const {0: '0', 1: '0.0', 2: '0.00'},
                    selected: settings.decimals.clamp(0, 2),
                    onChanged: (d) => _update((s) => s.copyWith(decimals: d)),
                  ),
                ),
                _LatePenaltyPanel(
                  percent: settings.latePenaltyPercent,
                  onChanged: (p) =>
                      _update((s) => s.copyWith(latePenaltyPercent: p)),
                ),
                SettingsSwitchTile(
                  hint: l.settingsLetterGradesHint,
                  title: l.settingsLetterGradesTitle,
                  value: settings.showLetterGrades,
                  onChanged: (v) =>
                      _update((s) => s.copyWith(showLetterGrades: v)),
                ),
              ],
            ),
            SettingsSection(
              label: l.settingsSectionFeedback,
              children: [
                SettingsLinkTile(
                  hint: l.settingsCommentBankHint,
                  title: l.settingsCommentBankTitle,
                  onTap: () => context.push(Routes.commentBank),
                ),
              ],
            ),
            SettingsSection(
              label: l.settingsSectionData,
              children: [
                SettingsLinkTile(
                  hint: l.settingsBackupHint,
                  title: l.settingsBackupTitle,
                  onTap: () => context.push(Routes.backup),
                ),
                SettingsLinkTile(
                  hint: _loadingSample
                      ? l.settingsSampleLoading
                      : l.settingsSampleHint,
                  title: l.settingsSampleTitle,
                  onTap: _loadingSample ? null : _loadSample,
                  trailing: _loadingSample ? const _Spinner() : null,
                ),
                SettingsLinkTile(
                  hint: l.settingsEraseHint,
                  title: l.settingsEraseTitle,
                  onTap: _erasing ? null : _eraseAll,
                  trailing: _erasing
                      ? const _Spinner()
                      : const FaIcon(
                          FontAwesomeIcons.trashCan,
                          color: accent,
                          size: 18,
                        ),
                ),
              ],
            ),
            SettingsSection(
              label: l.settingsSectionApp,
              children: [
                SettingsSwitchTile(
                  hint: l.settingsHapticsHint,
                  title: l.settingsHapticsTitle,
                  value: settings.haptics,
                  onChanged: _setHaptics,
                ),
                SettingsLinkTile(
                  hint: l.settingsOnboardingHint,
                  title: l.settingsOnboardingTitle,
                  onTap: _replayOnboarding,
                ),
                SettingsLinkTile(
                  hint: l.settingsAboutHint(appVersion),
                  title: l.settingsAboutTitle,
                  onTap: () => context.push(Routes.about),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

String _scaleName(AppLocalizations l, GradingScale scale) {
  final preset = ScalePreset.of(scale);
  return preset == null
      ? l.settingsScaleCustom(scale.bands.length)
      : presetName(l, preset);
}

class _Spinner extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
    );
  }
}

class _LatePenaltyPanel extends StatelessWidget {
  const new({required this.percent, required this.onChanged});

  final double percent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SettingsPanel(
      hint: l.settingsLatePenaltyHint,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: CardTitle(
                l.settingsLatePenaltyValue(formatPercent(percent)),
              ),
            ),
          ),
          SettingsRoundButton(
            icon: FontAwesomeIcons.minus,
            label: l.settingsLatePenaltyDecrease,
            onTap: percent <= 0
                ? null
                : () => onChanged(stepPenalty(percent, -1)),
          ),
          const SizedBox(width: Insets.sm),
          SettingsRoundButton(
            icon: FontAwesomeIcons.plus,
            label: l.settingsLatePenaltyIncrease,
            onTap: percent >= 100
                ? null
                : () => onChanged(stepPenalty(percent, 1)),
          ),
        ],
      ),
    );
  }
}

class _TeacherNameSheet extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_TeacherNameSheet> createState() => _TeacherNameSheetState();
}

class _TeacherNameSheetState extends State<_TeacherNameSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return RubricSheet(
      title: l.settingsTeacherNameSheetTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.settingsTeacherNameSheetMessage,
            style: RubricTextStyles.bodySmall,
          ),
          const SizedBox(height: Insets.lg),
          RubricFormWell(
            child: RubricTextField(
              controller: _controller,
              hintText: l.settingsTeacherNameFieldHint,
              semanticLabel: l.settingsTeacherNameHint,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(height: Insets.lg),
          FilledButton(onPressed: _save, child: Text(l.settingsSave)),
        ],
      ),
    );
  }
}
