import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';
import 'file_preview.dart';
export 'file_preview.dart';
export 'file_transfer.dart';

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

class FileCard extends StatefulWidget {
  final NekodotClient client;
  final String fileId, messageId;
  final String? botId;
  final Color? foreground;
  const FileCard({
    super.key,
    required this.client,
    required this.fileId,
    required this.messageId,
    this.botId,
    this.foreground,
  });
  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  late final nodeId = widget.client.selectedNodeId!;
  late final file = widget.client.rpc('files.get', {
    'fileId': widget.fileId,
  }, nodeId);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FutureBuilder<Json>(
      future: file,
      builder: (context, snapshot) => OutlinedButton.icon(
        style: widget.foreground == null
            ? null
            : OutlinedButton.styleFrom(
                foregroundColor: widget.foreground,
                side: BorderSide(
                  color: widget.foreground!.withValues(alpha: .4),
                ),
              ),
        onPressed: () async {
          try {
            final value = await file;
            if (context.mounted) {
              FilePreviewScope.open(
                context,
                widget.client,
                FileSelection(value, nodeId),
              );
            }
          } catch (e) {
            if (context.mounted) {
              showNotice(context, '$e');
            }
          }
        },
        icon: Icon(
          '${snapshot.data?['mime']}'.startsWith('image/')
              ? Icons.image_outlined
              : Icons.attach_file,
          size: 18,
        ),
        label: Text(
          snapshot.data?['name'] as String? ??
              widget.client.tr('附件', 'Attachment'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
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
  late final nodeId = widget.client.selectedNodeId!;
  @override
  Widget build(BuildContext context) => AsyncPane(
    key: ValueKey('$search:$type'),
    load: () => widget.client.rpc('files.list', {
      'botId': widget.bot['botId'],
      'search': search,
      if (type.isNotEmpty) 'type': type,
    }, nodeId),
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
                    onTap: () => FilePreviewScope.open(
                      context,
                      widget.client,
                      FileSelection(file, nodeId),
                    ),
                  ),
              ],
            ),
        ],
      );
    },
  );
}
