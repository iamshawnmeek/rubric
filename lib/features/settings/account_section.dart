import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/settings/settings_tiles.dart';
import 'package:rubric/features/sync/sync_status_view.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/sync/sync_service.dart';
import 'package:zonai_sync/zonai_sync.dart';

/// "Account & sync" at the top of Settings: sign in to back up and sync
/// across devices; once signed in, what sync is doing and what needs
/// attention.
class AccountSection extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final sync = ref.watch(syncServiceProvider);
    if (sync == null) return const SizedBox.shrink();
    // The stream only says "something changed"; the service holds the truth.
    ref.watch(syncStateProvider);
    final state = sync.state;
    final account = state.account;

    return SettingsSection(
      label: l.syncSectionTitle,
      children: [
        if (account == null)
          SettingsLinkTile(
            key: const Key('sync.signIn'),
            hint: l.syncSignedOutHint,
            title: l.syncSignInTitle,
            onTap: () => showRubricSheet<void>(
              context: context,
              child: const AccountSheet(),
            ),
            trailing: const FaIcon(
              FontAwesomeIcons.cloudArrowUp,
              color: primaryLightest,
              size: 18,
            ),
          )
        else ...[
          SettingsLinkTile(
            key: const Key('sync.status'),
            hint: account.email,
            title: syncStatusText(l, state.status),
            onTap: () => _onStatusTap(context, sync, state.status),
            trailing: SyncGlyph(status: state.status),
          ),
          for (final dead in state.status.deadLetters)
            SettingsLinkTile(
              hint: l.syncDeadLetterHint,
              title: l.syncDeadLetterTitle,
              onTap: () => _resolveDeadLetter(context, sync, dead),
              trailing: const FaIcon(
                FontAwesomeIcons.triangleExclamation,
                color: accent,
                size: 18,
              ),
            ),
          SettingsLinkTile(
            key: const Key('sync.signOut'),
            hint: l.syncSignOutHint,
            title: l.syncSignOutTitle,
            onTap: () => _signOut(context, sync),
            trailing: const FaIcon(
              FontAwesomeIcons.rightFromBracket,
              color: primaryLightest,
              size: 18,
            ),
          ),
          SettingsLinkTile(
            key: const Key('sync.deleteAccount'),
            hint: l.syncDeleteAccountHint,
            title: l.syncDeleteAccountTitle,
            onTap: () => _deleteAccount(context, sync),
            trailing: const FaIcon(
              FontAwesomeIcons.userXmark,
              color: primaryLightest,
              size: 18,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _onStatusTap(
    BuildContext context,
    SyncService sync,
    SyncStatus status,
  ) async {
    if (status.phase == SyncPhase.needsAuth) {
      await showRubricSheet<void>(
        context: context,
        child: const AccountSheet(reauthenticate: true),
      );
      return;
    }
    await sync.syncNow();
  }

  Future<void> _resolveDeadLetter(
    BuildContext context,
    SyncService sync,
    OutboxEntry dead,
  ) async {
    final l = context.l10n;
    final retry = await confirm(
      context,
      title: l.syncDeadLetterDialogTitle,
      message: l.syncDeadLetterDialogMessage(dead.lastError ?? ''),
      confirmLabel: l.syncDeadLetterRetry,
      cancelLabel: l.syncDeadLetterDiscard,
    );
    if (retry) {
      await sync.retryDeadLetter(dead.id);
    } else {
      await sync.discardDeadLetter(dead.id);
    }
  }

  Future<void> _signOut(BuildContext context, SyncService sync) async {
    final l = context.l10n;
    final pending = sync.state.status.pending;
    final sure = await confirm(
      context,
      title: l.syncSignOutConfirmTitle,
      message: pending > 0
          ? l.syncSignOutConfirmUnsynced(pending)
          : l.syncSignOutConfirmMessage,
      confirmLabel: l.syncSignOutTitle,
    );
    if (sure) await sync.signOut();
  }

  /// Required of any app that lets you create an account (App Store
  /// guideline 5.1.1(v)): deletion from inside the app, not by email.
  Future<void> _deleteAccount(BuildContext context, SyncService sync) async {
    final l = context.l10n;
    final sure = await confirm(
      context,
      title: l.syncDeleteAccountConfirmTitle,
      message: l.syncDeleteAccountConfirmMessage,
      confirmLabel: l.syncDeleteAccountConfirm,
    );
    if (!sure) return;
    try {
      await sync.deleteAccount();
      if (context.mounted) showRubricSnack(context, l.syncDeleteAccountDone);
    } on Object {
      if (context.mounted) showRubricSnack(context, l.syncDeleteAccountFailed);
    }
  }
}

/// Sign in or create an account, in the house bottom sheet.
class AccountSheet extends ConsumerStatefulWidget {
  const new({this.reauthenticate = false, super.key});

  /// The session expired: sign back in to the same account and resume.
  final bool reauthenticate;

  @override
  ConsumerState<AccountSheet> createState() => _AccountSheetState();
}

enum _Mode { signIn, create }

class _AccountSheetState extends ConsumerState<AccountSheet> {
  _Mode _mode = _Mode.signIn;
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final account = ref.read(syncServiceProvider)?.state.account;
    if (widget.reauthenticate && account != null) _email.text = account.email;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final sync = ref.read(syncServiceProvider);
    if (sync == null) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 8) {
      setState(() => _error = l.syncFormInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mode == _Mode.create) {
        await sync.signUp(email: email, password: password);
      } else {
        await sync.signIn(email: email, password: password);
      }
      if (widget.reauthenticate) await sync.resume();
      if (mounted) {
        Navigator.of(context).pop();
        showRubricSnack(context, l.syncSignedInSnack);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _mode == _Mode.create
              ? l.syncCreateFailed
              : l.syncSignInFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return RubricSheet(
      title: widget.reauthenticate ? l.syncReauthTitle : l.syncSheetTitle,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.reauthenticate) ...[
              SegmentedToggle<_Mode>(
                segments: {
                  _Mode.signIn: l.syncModeSignIn,
                  _Mode.create: l.syncModeCreate,
                },
                selected: _mode,
                onChanged: (m) => setState(() {
                  _mode = m;
                  _error = null;
                }),
              ),
              const SizedBox(height: Insets.lg),
              Text(l.syncSheetExplainer, style: RubricTextStyles.bodySmall),
              const SizedBox(height: Insets.lg),
            ],
            RubricFormWell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RubricTextField(
                    key: const Key('sync.email'),
                    controller: _email,
                    hintText: l.syncEmailLabel,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                  ),
                  const Divider(color: primaryLightest, height: Insets.xl),
                  RubricTextField(
                    key: const Key('sync.password'),
                    controller: _password,
                    hintText: _mode == _Mode.create
                        ? '${l.syncPasswordLabel} · ${l.syncPasswordHelp}'
                        : l.syncPasswordLabel,
                    semanticLabel: l.syncPasswordLabel,
                    obscureText: true,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    autofillHints: [
                      if (_mode == _Mode.create)
                        AutofillHints.newPassword
                      else
                        AutofillHints.password,
                    ],
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: RubricTextStyles.bodySmall.copyWith(color: accent),
                ),
              ),
            ],
            const SizedBox(height: Insets.xl),
            AccentButton(
              key: const Key('sync.submit'),
              label: _mode == _Mode.create
                  ? l.syncCreateAction
                  : l.syncSignInAction,
              onTap: _busy ? null : _submit,
              widthFactor: 0,
            ),
          ],
        ),
      ),
    );
  }
}
