import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/sync/account_tables.dart';
import 'package:rubric/sync/sync_tables.dart';

void main() {
  test('account deletion empties every synced table, children first', () {
    // syncTables is parents first, so its reverse is the safe order. A table
    // added there and not here would outlive the account that owns it.
    expect(accountDeletionOrder, [for (final t in syncTables.reversed) t.name]);
  });
}
