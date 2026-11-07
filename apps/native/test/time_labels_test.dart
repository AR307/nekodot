import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/data/client.dart';
import 'package:nekodot_native/features/time_labels.dart';

void main() {
  final c = NekodotClient();
  final now = DateTime(2026, 11, 7, 13, 20);

  test('The time between messages names the day once', () {
    expect(dividerTime(c, DateTime(2026, 11, 7, 9, 5), now), '今天 09:05');
    expect(dividerTime(c, DateTime(2026, 11, 6, 21, 55), now), '昨天 21:55');
    expect(dividerTime(c, DateTime(2026, 10, 25, 8, 0), now), '10月25日 08:00');
    expect(
      dividerTime(c, DateTime(2025, 12, 31, 23, 59), now),
      '2025年12月31日 23:59',
    );
  });

  test('A conversation row shows the time, then the day', () {
    expect(rowTime(c, DateTime(2026, 11, 7, 12, 53), now), '12:53');
    expect(rowTime(c, DateTime(2026, 11, 6, 23, 59), now), '昨天');
    // 2026-11-01 is a Sunday.
    expect(rowTime(c, DateTime(2026, 11, 1, 10, 0), now), '星期日');
    expect(rowTime(c, DateTime(2026, 10, 25, 10, 0), now), '10月25日');
  });
}
