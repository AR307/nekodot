import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekodot_native/ui/design.dart';
import 'package:nekodot_native/ui/prompt_card.dart';

void main() {
  testWidgets('capsule expands for typing, preserves text, and fits a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final input = TextEditingController();
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PromptCard(
                field: TextField(controller: input),
                hasContent: false,
                running: false,
                tools: const Text('Model'),
                action: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.mic),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PromptCard)).width, 320);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PromptCard)).width, 480);
    await tester.enterText(find.byType(TextField), '下一条草稿');
    expect(input.text, '下一条草稿');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PromptCard)).width,
      lessThanOrEqualTo(342),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
