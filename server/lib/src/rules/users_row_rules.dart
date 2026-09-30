import 'package:zonai_schema/zonai_schema.dart';
import 'package:rubric_server/src/schemas/users.dart';

UserRowRules main() => UserRowRules();

final class UserRowRules extends AuthRowRules<UserTable, User> {
  UserRowRules() : super(users);
}
