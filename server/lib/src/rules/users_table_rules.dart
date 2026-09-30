import 'package:zonai_schema/zonai_schema.dart';
import 'package:rubric_server/src/schemas/users.dart';

UserTableRules main() => UserTableRules();

final class UserTableRules extends AuthTableRules<UserTable, User> {
  UserTableRules() : super(users);
}
