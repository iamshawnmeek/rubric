import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/features/settings/erase_all_data.dart';

import '../../helpers/db.dart';
import 'seed.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = testDatabase());
  tearDown(() => db.close());

  test('erases every row of every table', () async {
    await seedEverything(db);
    final before = await rowCounts(db);
    expect(before.values, everyElement(greaterThan(0)), reason: '$before');

    await eraseAllData(db);

    final after = await rowCounts(db);
    expect(after.keys, before.keys);
    expect(after.values, everyElement(0), reason: '$after');
  });

  test('an empty database erases without error', () async {
    await eraseAllData(db);
    expect((await rowCounts(db)).values, everyElement(0));
  });
}
