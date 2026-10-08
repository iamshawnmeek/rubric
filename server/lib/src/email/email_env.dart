import 'package:zonai_schema/zonai_schema.dart';

/// Who Rubric's mail comes from: an approved sender on Oracle Email Delivery,
/// signed with yourrubric.com's DKIM key (docs/DEPLOY.md, "Email").
const rubricSender = EmailAddress(
  address: 'noreply@yourrubric.com',
  name: 'Rubric',
);

/// The SMTP settings, read from the process environment when the server
/// starts rather than compiled in.
///
/// Since zonai 0.10.2 (#73, which Rubric asked for) zonai itself overrides
/// `SMTP_USERNAME` and `SMTP_PASSWORD` from the environment, but only on an
/// email config that is already compiled in, and it accepts them empty. This
/// reader stays because it does what that doesn't:
/// - the host and port come from the environment too, so the email flow test
///   (tool/email/test_email_flow.sh) points a dev server at a local catcher;
/// - a release server without them refuses to start, instead of failing
///   every reset and verification email silently;
/// - plain SMTP is allowed only outside release.
/// The config runs in its own process on the host at startup, so nothing
/// here is ever baked into the bundle.
///
/// A release server without mail settings refuses to start: password reset
/// and email verification would otherwise fail silently for every teacher.
/// A development server without them simply sends no mail.
EmailConfig? emailConfigFrom(
  Map<String, String> environment, {
  required bool release,
}) {
  String? read(String name) {
    final value = environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  const required = ['SMTP_HOST', 'SMTP_USERNAME', 'SMTP_PASSWORD'];
  final missing = [
    for (final name in required)
      if (read(name) == null) name,
  ];
  if (missing.length == required.length && !release) return null;
  if (missing.isNotEmpty) {
    throw StateError(
      'Email is not configured: set ${missing.join(', ')} '
      '(in /etc/rubric/secrets.env on a server, see docs/DEPLOY.md).',
    );
  }

  final rawPort = read('SMTP_PORT') ?? '587';
  final port = int.tryParse(rawPort);
  if (port == null || port <= 0 || port > 65535) {
    throw StateError('SMTP_PORT is not a port: $rawPort');
  }

  return EmailConfig(
    host: read('SMTP_HOST')!,
    port: port,
    username: read('SMTP_USERNAME')!,
    password: read('SMTP_PASSWORD')!,
    from: rubricSender,
    // 465 is implicit TLS; 587 upgrades with STARTTLS.
    ssl: port == 465,
    // Only a development server may talk to a local plain-SMTP catcher.
    allowInsecure: !release && read('SMTP_ALLOW_INSECURE') == 'true',
  );
}
