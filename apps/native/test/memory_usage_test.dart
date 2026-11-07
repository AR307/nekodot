import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/features/memory_usage.dart';

void main() {
  test('editing native memory counts Unicode entries, not bytes or UTF-16', () {
    expect(nativeMemoryLength('  猫🐱  \r\n§\r\n猫🐱\r\n§\r\n A \r\n'), 6);
    expect(nativeMemoryLength('  \n§\n \n'), 0);
    expect(nativeMemoryLength('x§y'), 3);
    expect(nearMemoryLimit('a' * 1979, 2200), isFalse);
    expect(nearMemoryLimit('a' * 1980, 2200), isTrue);
    expect(nearMemoryLimit('a' * 2300, 2200), isTrue);
  });
}
