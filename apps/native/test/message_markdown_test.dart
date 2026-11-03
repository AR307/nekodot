import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:nekodot_native/ui/design.dart';
import 'package:nekodot_native/ui/message_markdown.dart';

void main() {
  test(
    'real Chinese model headings render without changing code or escapes',
    () {
      final html = md.markdownToHtml(
        '**摘要。**本研究\n\n**研究假设与边界。**H1\n\n'
        '`**摘要。**本研究`\n\n```text\n**摘要。**本研究\n```\n\n'
        r'\*\*摘要。\*\*本研究',
        inlineSyntaxes: [CjkStrongSyntax()],
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      expect(html, contains('<strong>摘要。</strong>本研究'));
      expect(html, contains('<strong>研究假设与边界。</strong>H1'));
      expect(html, contains('<code>**摘要。**本研究</code>'));
      expect(html, contains('<code class="language-text">**摘要。**本研究'));
      expect(html, contains('<p>**摘要。**本研究</p>'));
    },
  );

  testWidgets(
    'research reply renders headings, lists, tables and code at mobile width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: MessageMarkdown(
                data:
                    '# 论文构思\n\n**摘要。**研究真实工具调用。\n\n'
                    '- 检索文献\n- 验证方法\n\n'
                    '| 方法 | 成本 |\n| --- | --- |\n| 基线 | 1 |\n\n'
                    '> 未完成实验，不宣称有效。\n\n'
                    '```python\nprint("真实执行")\n```',
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('摘要。', findRichText: true), findsWidgets);
      expect(find.textContaining('**摘要。**', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
