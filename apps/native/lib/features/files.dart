import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../data/client.dart';
import '../ui/design.dart';
import 'bot_editor.dart';

Future<Uint8List> downloadFile(NekodotClient c, String id) async {
  final response = await http
      .get(
        c.url('/api/nodes/${c.selectedNodeId}/files/$id'),
        headers: {'Authorization': 'Bearer ${c.token}'},
      )
      .timeout(const Duration(minutes: 2));
  if (response.statusCode != 200) {
    throw RelayError('File HTTP ${response.statusCode}');
  }
  return response.bodyBytes;
}

// The same references the node turns into files: a MEDIA line, or a link or
// picture pointing at a path on the Bot's computer.
final _deliveryLine = RegExp(
  r'^[ \t]*MEDIA:[^\r\n]*(?:\r?\n)?',
  multiLine: true,
);
final _localReference = RegExp(
  r'(!?)\[([^\]]*)\]\(<?(?:sandbox:|file://|/|\./|~/|[A-Za-z]:[\/])[^)>]+>?\)',
);

/// A reply's words without what only delivered its files: those are shown
/// as files of their own.
String withoutDeliveries(String text) => text
    .replaceAll(_deliveryLine, '')
    .replaceAllMapped(_localReference, (m) => m[1]!.isEmpty ? m[2]! : '')
    .trim();

String fileSize(num bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1048576
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1048576).toStringAsFixed(1)} MB';

Future<Json?> pickChatFile(
  NekodotClient client,
  String conversationId,
  ValueChanged<String> onProgress, {
  String? localPath,
  Uint8List? imageBytes,
  bool imageOnly = false,
}) async {
  final nodeId = client.selectedNodeId!;
  final file = localPath == null && imageBytes == null
      ? await FilePicker.pickFile(
          type: imageOnly ? FileType.image : FileType.any,
        )
      : null;
  if (file == null && localPath == null && imageBytes == null) return null;
  final name =
      file?.name ??
      (localPath == null
          ? 'clipboard-${DateTime.now().millisecondsSinceEpoch}.png'
          : File(localPath).uri.pathSegments.last);
  final created = await client.rpc('imports.create', {}, nodeId);
  final importId = '${created['importId']}';
  final bytes =
      file?.readAsByteStream() ??
      (localPath == null
          ? Stream.value(imageBytes!)
          : File(localPath).openRead());
  var offset = 0;
  await for (final chunk in bytes) {
    for (var start = 0; start < chunk.length; start += 196608) {
      final end = (start + 196608).clamp(0, chunk.length);
      final response = await client.transport
          .put(
            client
                .url('/api/nodes/$nodeId/imports/$importId')
                .replace(queryParameters: {'path': name, 'offset': '$offset'}),
            headers: {
              'Authorization': 'Bearer ${client.token}',
              'Content-Type': 'application/octet-stream',
            },
            body: chunk.sublist(start, end),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw RelayError('Upload HTTP ${response.statusCode}');
      }
      offset += end - start;
      onProgress('$name · ${fileSize(offset)}');
    }
  }
  if (offset == 0) {
    final response = await client.transport.put(
      client
          .url('/api/nodes/$nodeId/imports/$importId')
          .replace(queryParameters: {'path': name, 'offset': '0'}),
      headers: {
        'Authorization': 'Bearer ${client.token}',
        'Content-Type': 'application/octet-stream',
      },
      body: <int>[],
    );
    if (response.statusCode != 200) {
      throw RelayError('Upload HTTP ${response.statusCode}');
    }
  }
  if (client.selectedNodeId != nodeId) {
    throw RelayError(
      client.tr(
        '电脑已切换，请在原会话重试',
        'Computer changed. Retry in the original conversation.',
      ),
    );
  }
  return client.rpc('files.receive', {
    'conversationId': conversationId,
    'importId': importId,
    'path': name,
  }, nodeId);
}

/// A file on its own line in the chat: a picture shows itself, anything else
/// is its name and size. Either opens the full file.
class FileCard extends StatefulWidget {
  final NekodotClient client;
  final String fileId, messageId;
  final String? botId;
  const FileCard({
    super.key,
    required this.client,
    required this.fileId,
    required this.messageId,
    this.botId,
  });
  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  late final file = widget.client.rpc('files.get', {'fileId': widget.fileId});
  Future<Uint8List>? picture;

  Future<void> open() async {
    try {
      final value = await file;
      if (mounted) {
        pushPage(context, FilePage(client: widget.client, file: value));
      }
    } catch (e) {
      if (mounted) showNotice(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: file,
    builder: (context, snapshot) {
      final value = snapshot.data;
      if (value != null &&
          value['available'] == true &&
          '${value['mime']}'.startsWith('image/')) {
        picture ??= downloadFile(widget.client, widget.fileId);
        return FutureBuilder<Uint8List>(
          future: picture,
          builder: (context, bytes) => bytes.hasError
              ? row(value)
              : image(bytes.data, '${value['name']}'),
        );
      }
      return row(value);
    },
  );

  Widget image(Uint8List? bytes, String name) {
    final tone = context.tone;
    final placeholder = Container(
      width: 240,
      height: 160,
      decoration: BoxDecoration(
        color: tone.bubble,
        borderRadius: BorderRadius.circular(12),
      ),
    );
    // The picture keeps its own proportions and is never shown larger than
    // its pixels.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: tone.glass ? double.infinity : 420,
        maxHeight: 360,
      ),
      child: bytes == null
          ? placeholder
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: open,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    bytes,
                    semanticLabel: name,
                    frameBuilder: (context, child, frame, sync) =>
                        frame == null && !sync ? placeholder : child,
                  ),
                ),
              ),
            ),
    );
  }

  Widget row(Json? value) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final corners = BorderRadius.circular(16);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: tone.surface,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          side: BorderSide(color: tone.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.bubble,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    value?['available'] == false
                        ? Icons.broken_image_outlined
                        : Icons.description_outlined,
                    size: 19,
                    color: tone.ink2,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value?['name'] as String? ??
                            widget.client.tr('附件', 'Attachment'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (value?['size'] is num)
                        Text(
                          fileSize(value!['size'] as num),
                          style: text.labelSmall?.copyWith(color: tone.ink3),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  final NekodotClient client;
  final Json bot;
  final bool embedded;
  const LibraryPage({
    super.key,
    required this.client,
    required this.bot,
    this.embedded = false,
  });
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String search = '', type = '';
  @override
  Widget build(BuildContext context) => AsyncPane(
    key: ValueKey('$search:$type'),
    load: () => widget.client.rpc('files.list', {
      'botId': widget.bot['botId'],
      'search': search,
      if (type.isNotEmpty) 'type': type,
    }),
    builder: (context, data, reload) {
      final files = objects(data['files']);
      return PageList(
        children: [
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: widget.client.tr('搜索', 'Search'),
            ),
            onSubmitted: (value) => setState(() => search = value),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children:
                {
                      '': widget.client.tr('全部', 'All'),
                      'image': widget.client.tr('图片', 'Images'),
                      'application/pdf': 'PDF',
                      'text': widget.client.tr('文本', 'Text'),
                    }.entries
                    .map(
                      (entry) => ChoiceChip(
                        label: Text(entry.value),
                        selected: type == entry.key,
                        onSelected: (_) => setState(() => type = entry.key),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 14),
          if (files.isNotEmpty)
            PanelGroup(
              children: [
                for (final file in files)
                  ListTile(
                    leading: Icon(
                      file['available'] == true
                          ? Icons.description_outlined
                          : Icons.broken_image_outlined,
                    ),
                    title: Text('${file['name']}'),
                    subtitle: Text(fileSize(file['size'] as num)),
                    onTap: () => pushPage(
                      context,
                      FilePage(client: widget.client, file: file),
                    ),
                  ),
              ],
            ),
        ],
      );
    },
  );
}

class FilePage extends StatefulWidget {
  final NekodotClient client;
  final Json file;
  const FilePage({super.key, required this.client, required this.file});
  @override
  State<FilePage> createState() => _FilePageState();
}

class _FilePageState extends State<FilePage> {
  NekodotClient get client => widget.client;
  Json get file => widget.file;
  late final content = downloadFile(client, file['fileId'] as String);
  bool busy = false;
  String error = '', notice = '';

  Future<void> deliver({required bool share}) async {
    setState(() {
      busy = true;
      error = '';
      notice = '';
    });
    try {
      final bytes = await content;
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: file['mime'] as String)],
            fileNameOverrides: [file['name'] as String],
          ),
        );
      } else {
        final saved = await FilePicker.saveFile(
          dialogTitle: client.tr('保存文件', 'Save file'),
          fileName: file['name'] as String,
          mimeType: file['mime'] as String,
          bytes: bytes,
        );
        if (saved != null && mounted) {
          setState(() => notice = client.tr('文件已保存', 'File saved'));
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '${file['name']}',
    actions: [
      IconButton(
        tooltip: client.tr('分享文件', 'Share file'),
        onPressed: file['available'] == true && !busy
            ? () => deliver(share: true)
            : null,
        icon: const Icon(Icons.ios_share_outlined),
      ),
      IconButton(
        tooltip: client.tr('保存文件', 'Save file'),
        icon: const Icon(Icons.download_outlined),
        onPressed: file['available'] != true || busy
            ? null
            : () => deliver(share: false),
      ),
    ],
    body: SafeArea(
      child: Column(
        children: [
          if (RegExp(r'\.(tar\.gz|tgz)$').hasMatch('${file['name']}') &&
              file['available'] == true)
            TextButton.icon(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(client.tr('作为新 Bot 导入', 'Import as a new Bot')),
              onPressed: () => pushPage(
                context,
                BotEditor(
                  client: client,
                  importProfile: true,
                  initialArchive: file,
                ),
              ),
            ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorNotice(error),
            ),
          if (notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(notice, style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(
            child: file['available'] != true
                ? const Center(
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  )
                : FutureBuilder<Uint8List>(
                    future: content,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: ErrorNotice('${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: Breathing());
                      }
                      final bytes = snapshot.data!,
                          mime = file['mime'] as String;
                      if (mime.startsWith('image/')) {
                        return InteractiveViewer(
                          child: Center(child: Image.memory(bytes)),
                        );
                      }
                      if (mime == 'application/pdf') {
                        return PdfViewer.data(
                          bytes,
                          sourceName: file['name'] as String,
                        );
                      }
                      if (mime.startsWith('text/') ||
                          mime == 'application/json') {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: SelectableText(
                            utf8.decode(bytes, allowMalformed: true),
                          ),
                        );
                      }
                      return Center(
                        child: Icon(
                          Icons.description_outlined,
                          size: 48,
                          color: context.tone.ink3,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
