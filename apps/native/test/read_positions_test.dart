import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nekodot_native/data/read_positions.dart';

void main() {
  test(
    'new device ignores old history and keeps unread through restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final positions = ReadPositions();
      await positions.load('account-a');
      await positions.baseline('node-a', 100);
      expect(positions.unread('node-a', 'chat-a', 90), isFalse);
      expect(positions.unread('node-a', 'chat-a', 101), isTrue);
      await positions.viewed('node-a', 'chat-a', 101);
      expect(positions.unread('node-a', 'chat-a', 101), isFalse);
      expect(positions.unread('node-a', 'chat-b', 101), isTrue);
      await positions.received('node-a', 'chat-b', 101);
      final restarted = ReadPositions();
      await restarted.load('account-a');
      await restarted.baseline('node-a', 200);
      expect(restarted.unread('node-a', 'chat-a', 101), isFalse);
      expect(restarted.unread('node-a', 'chat-b', 101), isTrue);
      // The newest summary can be an outgoing message; it must not erase an
      // unread reply that this device received before restarting.
      expect(restarted.unread('node-a', 'chat-b', 0), isTrue);
      await restarted.load('account-b');
      await restarted.baseline('node-a', 200);
      expect(restarted.unread('node-a', 'chat-b', 101), isFalse);
      positions.dispose();
      restarted.dispose();
    },
  );
}
