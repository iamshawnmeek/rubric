import 'package:rubric_server/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// The public website, which hosts the pages the emailed links open
/// (website/reset-password.html, website/verify-email.html). zonai serves no
/// pages of its own, and a teacher may open the email on a computer without
/// the app, so the links go to the site rather than into the app.
const siteUrl = String.fromEnvironment(
  'RUBRIC_SITE_URL',
  defaultValue: 'https://yourrubric.com',
);

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);

  /// zonai's default is 10 minutes. A teacher who requests a reset between
  /// classes may not open the email that quickly; 30 minutes still leaves a
  /// leaked link little time to be useful.
  @override
  Future<ResetPasswordConfig> resetPasswordConfig() async =>
      ResetPasswordConfig(
        path: '$siteUrl/reset-password',
        expiresIn: const Duration(minutes: 30),
      );

  @override
  Future<VerifyEmailConfig> verifyEmailConfig() async =>
      VerifyEmailConfig(path: '$siteUrl/verify-email');
}

UserOperations main() => UserOperations();
