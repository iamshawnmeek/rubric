import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/backup_service.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/export/backup_state.dart';
import 'package:rubric/features/export/csv_builders.dart' show isoDate;
import 'package:rubric/features/export/export_platform.dart';
import 'package:rubric/features/export/restore_sheet.dart';
import 'package:rubric/l10n/l10n.dart';

/// Back up everything on the device to one JSON file, or restore from one.
class BackupPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

enum _Busy {
  idle,
  backingUp,

  /// A picker, sheet or dialog is open: actions are disabled, no spinner.
  choosing,
  reading,
  restoring,
}

class _BackupPageState extends ConsumerState<BackupPage> {
  _Busy _busy = _Busy.idle;

  bool get _idle => _busy == _Busy.idle;

  Future<void> _run(_Busy busy, Future<void> Function() work) async {
    if (!_idle) return;
    setState(() => _busy = busy);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = _Busy.idle);
    }
  }

  Future<void> _backup() => _run(_Busy.backingUp, () async {
    final l10n = context.l10n;
    final now = DateTime.now();
    try {
      final json = await ref
          .read(backupServiceProvider)
          .export(settings: ref.read(settingsProvider).toJson(), now: now);
      final shared = await ref
          .read(exportPlatformProvider)
          .shareFile(
            bytes: Uint8List.fromList(utf8.encode(json)),
            filename: 'rubric-backup-${isoDate.format(now)}.json',
            mimeType: 'application/json',
            subject: l10n.backupShareSubject,
            origin: _origin(),
          );
      if (!shared) return;
      await ref.read(lastBackupProvider.notifier).record(now);
      if (mounted) showRubricSnack(context, l10n.backupDone);
    } on Object catch (error) {
      debugPrint('Backup failed: $error');
      if (mounted) showRubricSnack(context, l10n.backupFailed);
    }
  });

  /// Pick → validate → summary sheet → (confirm) → restore. The spinner only
  /// shows while work is happening, never behind a sheet the user is reading.
  Future<void> _restore() async {
    if (!_idle) return;
    final l10n = context.l10n;
    final service = ref.read(backupServiceProvider);
    void phase(_Busy busy) {
      if (mounted) setState(() => _busy = busy);
    }

    phase(_Busy.choosing);
    try {
      final BackupDocument doc;
      final RestorePreview preview;
      try {
        final file = await ref.read(exportPlatformProvider).pickBackupFile();
        if (file == null) return;
        phase(_Busy.reading);
        doc = BackupService.parse(
          utf8.decode(file.bytes, allowMalformed: true),
        );
        preview = await service.preview(doc);
      } on BackupException catch (e) {
        debugPrint('$e');
        phase(_Busy.choosing);
        if (mounted) await _showProblem(e.problem);
        return;
      } on Object catch (error) {
        debugPrint('Reading backup failed: $error');
        if (mounted) showRubricSnack(context, l10n.backupReadFailed);
        return;
      }

      phase(_Busy.choosing);
      if (!mounted) return;
      final mode = await showRestoreSheet(context, doc: doc, preview: preview);
      if (mode == null || !mounted) return;
      if (mode == RestoreMode.replace &&
          !await confirm(
            context,
            title: l10n.backupReplaceConfirmTitle,
            message: l10n.backupReplaceConfirmMessage,
            confirmLabel: l10n.backupReplaceConfirmAction,
          )) {
        return;
      }

      phase(_Busy.restoring);
      final settings = ref.read(settingsProvider);
      try {
        // Taken first so the restore can be undone exactly.
        final before = await service.snapshot(settings: settings.toJson());
        await service.restore(doc, mode: mode);
        if (mode == RestoreMode.replace && doc.settings != null) {
          await _applySettings(doc.settings!);
        }
        ref.invalidate(deviceContentsProvider);
        if (!mounted) return;
        showRubricSnack(
          context,
          l10n.backupRestored(doc.totalRecords),
          action: SnackBarAction(
            label: l10n.backupUndo,
            onPressed: () => _undo(before),
          ),
        );
      } on Object catch (error) {
        debugPrint('Restore failed: $error');
        if (mounted) showRubricSnack(context, l10n.backupRestoreFailed);
      }
    } finally {
      phase(_Busy.idle);
    }
  }

  Future<void> _undo(BackupDocument before) => _run(_Busy.restoring, () async {
    final l10n = context.l10n;
    try {
      await ref
          .read(backupServiceProvider)
          .restore(before, mode: RestoreMode.replace);
      if (before.settings != null) await _applySettings(before.settings!);
      ref.invalidate(deviceContentsProvider);
      if (mounted) showRubricSnack(context, l10n.backupUndone);
    } on Object catch (error) {
      debugPrint('Undo restore failed: $error');
      if (mounted) showRubricSnack(context, l10n.backupRestoreFailed);
    }
  });

  /// Restored preferences never send the teacher back through onboarding.
  Future<void> _applySettings(Map<String, dynamic> json) async {
    final AppSettings restored;
    try {
      restored = AppSettings.fromJson(json);
    } on Object {
      return; // Data restored; unreadable settings are simply kept as they are.
    }
    await ref
        .read(settingsProvider.notifier)
        .update((_) => restored.copyWith(onboardingComplete: true));
  }

  Future<void> _showProblem(BackupProblem problem) {
    final l10n = context.l10n;
    return showRubricSheet<void>(
      context: context,
      child: RubricSheet(
        title: l10n.backupProblemTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch (problem) {
              BackupProblem.notJson => l10n.backupProblemNotJson,
              BackupProblem.wrongFormat => l10n.backupProblemWrongFormat,
              BackupProblem.newerVersion => l10n.backupProblemNewerVersion,
              BackupProblem.unsupportedVersion =>
                l10n.backupProblemUnsupportedVersion,
              BackupProblem.corrupt => l10n.backupProblemCorrupt,
            }, style: RubricTextStyles.pageInfo.copyWith(fontSize: 20)),
            const SizedBox(height: Insets.xl),
            Builder(
              builder: (context) => AccentButton(
                label: l10n.backupProblemDismiss,
                widthFactor: .2,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Rect? _origin() {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final last = ref.watch(lastBackupProvider);
    final contents = ref.watch(deviceContentsProvider);

    return RubricPage(
      title: l10n.backupTitle,
      bottomCta: AccentButton(
        key: const ValueKey('backupNow'),
        label: _busy == _Busy.backingUp
            ? l10n.backupWorking
            : l10n.backupNowAction,
        widthFactor: .2,
        enabled: _idle,
        onTap: _backup,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.backupIntro, style: RubricTextStyles.bodySmall),
                const SizedBox(height: Insets.lg),
                RubricCard(
                  key: const ValueKey('lastBackup'),
                  cardHintText: l10n.backupLastHint,
                  cardTitleText: last == null
                      ? l10n.backupNever
                      : DateFormat.yMMMMd(l10n.localeName)
                            .add_jm()
                            .format(last),
                  trailing: FaIcon(
                    last == null
                        ? FontAwesomeIcons.triangleExclamation
                        : FontAwesomeIcons.circleCheck,
                    color: last == null ? accent : primaryLighter,
                  ),
                ),
                SectionLabel(l10n.backupOnDevice),
                AsyncView(
                  value: contents,
                  data: (doc) => RubricCard(
                    key: const ValueKey('deviceContents'),
                    cardHintText: l10n.backupCountRecords(doc.totalRecords),
                    cardTitleText: [
                      l10n.backupCountClasses(doc.courses.length),
                      l10n.backupCountStudents(doc.students.length),
                    ].join(' · '),
                    footer: Text(
                      backupContentLines(l10n, doc).join(' · '),
                      style: RubricTextStyles.caption,
                    ),
                  ),
                ),
                SectionLabel(l10n.backupRestoreSection),
                RubricCard(
                  key: const ValueKey('restore'),
                  cardHintText: l10n.backupRestoreHint,
                  cardTitleText: l10n.backupRestoreAction,
                  onTap: _idle ? _restore : null,
                  trailing: _busy == _Busy.reading || _busy == _Busy.restoring
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            color: accent,
                            strokeWidth: 3,
                          ),
                        )
                      : const FaIcon(
                          FontAwesomeIcons.chevronRight,
                          color: primaryLightest,
                        ),
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  l10n.backupRestoreExplain,
                  style: RubricTextStyles.caption,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
