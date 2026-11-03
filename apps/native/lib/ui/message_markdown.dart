import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'design.dart';

/// Chinese prose commonly places bold punctuation directly before the next word.
/// Extend the parser at that boundary instead of rewriting stored model output.
class CjkStrongSyntax extends md.InlineSyntax {
  CjkStrongSyntax()
    : super(
        r'(?<!\*)\*\*(?!\*)(?=\S)((?:(?!\*\*).)*?[。！？：；，、”’）》】])\*\*(?=[A-Za-z0-9\u3040-\u30ff\u3400-\u9fff])',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element('strong', md.InlineParser(match[1]!, parser.document).parse()),
    );
    return true;
  }
}

class MessageMarkdown extends StatelessWidget {
  final String data;
  final Color? color;
  const MessageMarkdown({super.key, required this.data, this.color});

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    selectable: true,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    inlineSyntaxes: [CjkStrongSyntax()],
    styleSheet: markdownStyle(context, color: color),
    onTapLink: (_, href, _) {
      if (href != null) {
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      }
    },
  );
}
