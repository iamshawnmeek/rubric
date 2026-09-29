import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/settings/app_info.dart';
import 'package:rubric/features/settings/settings_tiles.dart';
import 'package:rubric/l10n/l10n.dart';

/// Version, the story of the app, who made it, licenses and the privacy
/// promise.
class AboutPage extends StatelessWidget {
  const new({super.key});

  void _showLicenses(BuildContext context) {
    final l = context.l10n;
    showLicensePage(
      context: context,
      applicationName: l.appTitle,
      applicationVersion: l.settingsAboutVersion(appVersion),
      applicationIcon: const Padding(
        padding: EdgeInsets.all(Insets.md),
        child: RubricLogo(width: 160, height: 48),
      ),
      useRootNavigator: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return RubricPage(
      title: l.settingsAboutPageTitle,
      children: [
        SettingsColumn(
          children: [
            const Center(child: RubricLogo(width: 220, height: 66)),
            const SizedBox(height: Insets.sm),
            Text(
              l.settingsAboutVersion(appVersion),
              textAlign: TextAlign.center,
              style: RubricTextStyles.caption,
            ),
            const SizedBox(height: Insets.lg),
            _AboutCard(
              hint: l.settingsAboutStoryHint,
              title: l.settingsAboutStoryTitle,
              body: l.settingsAboutStoryBody,
            ),
            const SizedBox(height: Insets.sm),
            _AboutCard(
              hint: l.settingsAboutPrivacyHint,
              title: l.settingsAboutPrivacyTitle,
              body: l.settingsAboutPrivacyBody,
              icon: FontAwesomeIcons.lock,
            ),
            const SizedBox(height: Insets.sm),
            _AboutCard(
              hint: l.settingsAboutCreditsHint,
              title: l.settingsAboutCreditsTitle,
              body: l.settingsAboutCreditsBody,
            ),
            const SizedBox(height: Insets.sm),
            SettingsLinkTile(
              hint: l.settingsAboutLicensesHint,
              title: l.settingsAboutLicensesTitle,
              onTap: () => _showLicenses(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// A primaryCard with hint, title and a paragraph of body copy.
class _AboutCard extends StatelessWidget {
  const new({
    required this.hint,
    required this.title,
    required this.body,
    this.icon,
  });

  final String hint;
  final String title;
  final String body;
  final FaIconData? icon;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: Insets.card,
        decoration: BoxDecoration(
          color: primaryCard,
          borderRadius: Corners.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: CardHint(hint)),
                if (icon != null) FaIcon(icon, color: primaryLighter, size: 16),
              ],
            ),
            const SizedBox(height: Insets.xs),
            CardTitle(title),
            const SizedBox(height: Insets.sm),
            Text(
              body,
              style: RubricTextStyles.bodySmall.copyWith(color: white),
            ),
          ],
        ),
      ),
    );
  }
}
