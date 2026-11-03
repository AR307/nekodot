import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/platform/updates.dart';

void main() {
  test('version check offers a newer build without suggesting downgrades', () {
    final artifact = {
      'path': 'releases/0.3.10-12/nekodot-update.exe',
      'size': 128,
      'build': 12,
    };
    final release = ProductRelease({
      'schema': 1,
      'version': '0.3.10',
      'build': 12,
      'notes': '',
      'artifacts': {'windows': artifact, 'android': artifact},
    }, Uri.parse('https://nekodot.example'));
    expect(release.newerThan(const InstalledVersion('0.3.9', 99)), isTrue);
    expect(release.newerThan(const InstalledVersion('0.3.10', 11)), isTrue);
    expect(release.newerThan(const InstalledVersion('0.3.10', 12)), isFalse);
    expect(release.newerThan(const InstalledVersion('0.4.0', 1)), isFalse);
    expect(release.download.host, 'nekodot.example');
  });
}
