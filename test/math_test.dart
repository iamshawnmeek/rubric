import 'package:flutter_test/flutter_test.dart';

void main() {
  test('less minus greater', () {
    final previous = 10.0;
    final next = 40.0;
    final offset = previous - next;
    final absolute = offset.abs();

    expect(absolute, 30);
  });

  test('greater minus less', () {
    final previous = 40.0;
    final next = 10.0;
    final offset = previous - next;
    final absolute = offset.abs();

    expect(absolute, 30);
  });
}
