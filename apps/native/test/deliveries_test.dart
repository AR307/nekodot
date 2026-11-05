import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/features/files.dart';

void main() {
  test('A reply hides what only delivered its files', () {
    expect(
      withoutDeliveries(
        'Here is the chart.\nMEDIA: D:\\work\\chart.png\n'
        'MEDIA:"/root/report one.txt"\n\n'
        '![chart](D:/work/chart.png) and [the notes](/root/notes.md).',
      ),
      'Here is the chart.\n\n and the notes.',
    );
    expect(
      withoutDeliveries('See [the site](https://nekodot.com) for more.'),
      'See [the site](https://nekodot.com) for more.',
    );
  });
}
