import 'dart:convert';
import 'dart:typed_data';

import '../data/client.dart';

Future<Uint8List> downloadFile(
  NekodotClient client,
  String id, {
  required String nodeId,
}) async {
  final response = await client.transport
      .get(
        client.url(
          '/api/nodes/${Uri.encodeComponent(nodeId)}/files/${Uri.encodeComponent(id)}',
        ),
        headers: {'Authorization': 'Bearer ${client.token}'},
      )
      .timeout(const Duration(minutes: 2));
  if (response.statusCode != 200) {
    throw RelayError('File HTTP ${response.statusCode}');
  }
  return response.bodyBytes;
}

bool isSvgFile(Json file) =>
    '${file['mime']}'.split(';').first.trim().toLowerCase() ==
        'image/svg+xml' ||
    '${file['name']}'.toLowerCase().endsWith('.svg');

/// Keep the original XML in an image-only browser context. SVG image documents
/// do not execute scripts, navigate links or load external resources.
String svgPreviewDocument(List<int> bytes, {double scale = 1}) {
  final extent = (scale.clamp(.25, 4) * 100).round();
  return '''<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;min-width:100%;min-height:100%;background:#f4f4f4}
.canvas{width:${extent}vw;height:${extent}vh;min-width:100vw;min-height:100vh;display:grid;place-items:center}
img{display:block;width:${extent}vw;height:${extent}vh;object-fit:contain}</style></head>
<body><div class="canvas"><img alt="SVG" src="data:image/svg+xml;base64,${base64Encode(bytes)}"></div></body></html>''';
}

String safeAttachmentName(String name) {
  var result = name
      .split(RegExp(r'[/\\]'))
      .last
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (result.isEmpty) return 'attachment';
  if (RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(result)) {
    result = '_$result';
  }
  // Bound a single path component while retaining the extension.
  if (result.length > 180) {
    final dot = result.lastIndexOf('.');
    final extension = dot > 0 && result.length - dot <= 20
        ? result.substring(dot)
        : '';
    result = '${result.substring(0, 180 - extension.length)}$extension';
  }
  return result;
}

String readableMessageText(String text, {required bool hasFiles}) {
  if (!hasFiles) return text;
  String? fence;
  final lines = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    final marker = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line)?.group(1);
    if (marker != null) {
      if (fence == null) {
        fence = marker;
      } else if (marker[0] == fence[0] && marker.length >= fence.length) {
        fence = null;
      }
      lines.add(line);
    } else if (fence != null || !RegExp(r'^\s*MEDIA:\s*\S').hasMatch(line)) {
      lines.add(line);
    }
  }
  return lines.join('\n').trim();
}
