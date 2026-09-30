import 'package:zonai_schema/zonai_schema.dart';

/// Development defaults. A deployment injects real secrets at runtime
/// (ZONAI_JWT_SECRET / ZONAI_PASSWORD_SECRET) -- never ship these.
AppConfig main() {
  return AppConfig(
    appName: 'Rubric',
    passwordSecret: const String.fromEnvironment(
      'RUBRIC_PASSWORD_SECRET',
      defaultValue: 'dev-only-rubric-password-pepper-7Qm2Xv9Lk4',
    ),
    jwtSecret: const String.fromEnvironment(
      'RUBRIC_JWT_SECRET',
      defaultValue: 'dev-only-rubric-jwt-secret-Hn3Wc8Tz5Rp1Yd6',
    ),
    baseUrl: 'http://localhost:8792',
  );
}
