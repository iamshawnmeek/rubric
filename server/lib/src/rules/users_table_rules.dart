import 'package:zonai_schema/zonai_schema.dart';
import 'package:rubric_server/src/schemas/users.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);

  /// Signed-in teachers may delete (their account: App Store guideline
  /// 5.1.1(v)). zonai's default is admins only; AuthRowRules.canDelete then
  /// limits it to the caller's own row.
  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt != null;
}
