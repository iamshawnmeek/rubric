import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/backup_service.dart';
import 'package:rubric/data/providers.dart';

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

/// When the user last completed a backup (shared the file), or null.
final lastBackupProvider = NotifierProvider<LastBackupNotifier, DateTime?>(
  LastBackupNotifier.new,
);

class LastBackupNotifier extends Notifier<DateTime?> {
  static const key = 'backup.lastAt';

  @override
  DateTime? build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(key);
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> record(DateTime at) async {
    state = at;
    await ref
        .read(sharedPreferencesProvider)
        .setString(key, at.toUtc().toIso8601String());
  }
}

/// What is on this device right now, for the backup page's summary card.
/// Invalidate after a restore.
final FutureProvider<BackupDocument> deviceContentsProvider =
    FutureProvider.autoDispose<BackupDocument>(
      (ref) => ref.watch(backupServiceProvider).snapshot(),
    );
