import 'package:rubric_server/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Rate limits for the auth routes of the `users` table, per client IP.
///
/// zonai's default is 100 requests a minute on every auth route. For the
/// routes that send email that is a hole: one IP could mail a stranger a
/// password reset or a confirmation link a hundred times a minute, through
/// Rubric's address and its 3,000-a-month Oracle Email Delivery allowance.
/// zonai's own per-address cooldown (one email a minute to the same
/// address) doesn't stop one email each to many addresses.
///
/// The limits are looser than zonai's suggestions on purpose: a school's
/// teachers often share one public IP, and a staff training session can
/// mean a room of them signing up at once. Counted per real client IP
/// since `trustedProxy` (server/lib/src/config/app_config.dart).
final class UserRateLimits extends AuthTableRateLimits<UserTable, User> {
  UserRateLimits() : super(users);

  /// `POST /auth`: the app's sign-up goes through it.
  @override
  Future<RateLimitPolicy?> authenticatePolicy() async =>
      const RateLimitPolicy(maxRequests: 30, window: Duration(minutes: 15));

  @override
  Future<RateLimitPolicy?> signInPolicy() async =>
      const RateLimitPolicy(maxRequests: 30, window: Duration(minutes: 15));

  @override
  Future<RateLimitPolicy?> signUpPolicy() async =>
      const RateLimitPolicy(maxRequests: 30, window: Duration(hours: 1));

  /// Sends email.
  @override
  Future<RateLimitPolicy?> sendResetPasswordPolicy() async =>
      const RateLimitPolicy(maxRequests: 10, window: Duration(hours: 1));

  /// Sends email.
  @override
  Future<RateLimitPolicy?> sendVerifyEmailPolicy() async =>
      const RateLimitPolicy(maxRequests: 10, window: Duration(hours: 1));
}

UserRateLimits main() => UserRateLimits();
