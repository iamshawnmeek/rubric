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
/// zonai only takes `JWT_SECRET` and `PASSWORD_SECRET` from the environment
/// (`AppConfig.withSecretsFromEnvironment`); anything else in the config is
/// baked into the binary as a define, where `strings` recovers it. The config
/// runs in its own process on the host at startup, so reading the SMTP
/// password here keeps it in `/etc/rubric/secrets.env` with the other secrets
/// and out of the bundle.
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
