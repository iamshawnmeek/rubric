import 'dart:io';

import 'package:rubric_server/src/email/email_env.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Set by a production build (`tool/deploy/build.sh` writes it into
/// `.env.prod`). Development builds leave it false.
const _release = bool.fromEnvironment('RUBRIC_RELEASE');

/// Development builds carry these fixed dev-only secrets, so a local server
/// starts with no setup. A release build carries NO secrets: the signing
/// secrets reach the process at runtime (`JWT_SECRET` and `PASSWORD_SECRET`
/// from the host's root-only env file, see docs/DEPLOY.md). A runtime value
/// always wins over a compiled one, and zonai refuses to start without
/// valid secrets, so a release server missing its secrets fails closed
/// instead of quietly signing tokens with a published dev secret. The SMTP
/// settings arrive the same way ([emailConfigFrom]).
AppConfig main() {
  return AppConfig(
    appName: 'Rubric',
    passwordSecret: _release
        ? ''
        : 'dev-only-rubric-password-pepper-7Qm2Xv9Lk4',
    jwtSecret: _release ? '' : 'dev-only-rubric-jwt-secret-Hn3Wc8Tz5Rp1Yd6',
    baseUrl: const String.fromEnvironment(
      'RUBRIC_BASE_URL',
      defaultValue: 'http://localhost:8792',
    ),
    email: emailConfigFrom(Platform.environment, release: _release),
  );
}
