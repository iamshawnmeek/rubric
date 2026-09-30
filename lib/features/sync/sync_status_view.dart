import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:zonai_sync/zonai_sync.dart';

/// One line describing what sync is doing, for a teacher.
String syncStatusText(AppLocalizations l, SyncStatus status) =>
    switch (status.phase) {
      SyncPhase.needsAuth => l.syncStatusNeedsAuth,
      SyncPhase.offline => l.syncStatusOffline(status.pending),
      SyncPhase.pushing || SyncPhase.pulling => l.syncStatusSyncing,
      _ when status.deadLetters.isNotEmpty => l.syncStatusAttention(
        status.deadLetters.length,
      ),
      _ when status.pending > 0 => l.syncStatusPending(status.pending),
      _ => l.syncStatusSynced,
    };

/// A cloud icon reflecting sync state. Never colour alone: the tile beside
/// it always carries the words.
class SyncGlyph extends StatelessWidget {
  const new({required this.status, super.key});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status.phase) {
      SyncPhase.needsAuth => (FontAwesomeIcons.userLock, accent),
      SyncPhase.offline => (FontAwesomeIcons.cloud, inactive),
      SyncPhase.pushing ||
      SyncPhase.pulling => (FontAwesomeIcons.arrowsRotate, primaryLighter),
      _ when status.deadLetters.isNotEmpty => (
        FontAwesomeIcons.triangleExclamation,
        accent,
      ),
      _ => (FontAwesomeIcons.cloudArrowUp, primaryLightest),
    };
    return ExcludeSemantics(child: FaIcon(icon, color: color, size: 18));
  }
}

/// The compact sync indicator in Home's header: shown only while signed in,
/// it opens Settings, where the full status and its actions live.
class SyncIndicator extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);
    if (sync == null) return const SizedBox.shrink();
    // The stream only says "something changed"; the service holds the truth.
    ref.watch(syncStateProvider);
    final state = sync.state;
    if (!state.signedIn) return const SizedBox.shrink();
    final l = context.l10n;
    return IconButton(
      key: const Key('sync.indicator'),
      tooltip: l.syncHomeBadge(syncStatusText(l, state.status)),
      onPressed: () => context.go(Routes.settings),
      icon: SyncGlyph(status: state.status),
    );
  }
}
