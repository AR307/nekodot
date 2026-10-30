import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../data/client.dart';
import '../ui/design.dart';

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

class FileCard extends StatelessWidget {
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: OutlinedButton.icon(
      onPressed: () async {
        try {
          final files = objects(
            (await client.rpc('files.list', {
              'botId': botId,
              'messageId': messageId,
            }))['files'],
          );
          final file = files.firstWhere((x) => x['fileId'] == fileId);
          if (context.mounted) {
            pushPage(context, FilePage(client: client, file: file));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      },
      icon: const Icon(Icons.attach_file),
      label: Text(client.tr('查看附件', 'View attachment')),
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
  @override
  Widget build(BuildContext context) => AsyncPane(
    key: ValueKey('$search:$type'),
    load: () => widget.client.rpc('files.list', {
      'botId': widget.bot['botId'],
      'search': search,
      if (type.isNotEmpty) 'type': type,
    }),
    builder: (context, data, reload) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: widget.client.tr('搜索文件名', 'Search files'),
          ),
          onSubmitted: (value) => setState(() => search = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
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
        const SizedBox(height: 16),
        for (final file in objects(data['files']))
          Card(
            child: ListTile(
              leading: Icon(
                file['available'] == true
                    ? Icons.insert_drive_file_outlined
                    : Icons.broken_image_outlined,
              ),
              title: Text('${file['name']}'),
              subtitle: Text('${file['mime']} · ${file['size']} B'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushPage(
                context,
                FilePage(client: widget.client, file: file),
              ),
            ),
          ),
      ],
    ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${file['name']}'),
      actions: [
        IconButton(
          tooltip: client.tr('分享文件', 'Share file'),
          onPressed: file['available'] == true && !busy
              ? () => deliver(share: true)
              : null,
          icon: const Icon(Icons.share_outlined),
        ),
        IconButton(
          tooltip: client.tr('保存文件', 'Save file'),
          icon: const Icon(Icons.download_outlined),
          onPressed: file['available'] != true || busy
              ? null
              : () => deliver(share: false),
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorNotice(error),
          ),
        if (notice.isNotEmpty)
          Padding(padding: const EdgeInsets.all(8), child: Text(notice)),
        Expanded(
          child: file['available'] != true
              ? Center(
                  child: Text(
                    client.tr(
                      '原文件已不可读取，保留此来源记录。',
                      'The original file is unavailable. Its source is retained.',
                    ),
                  ),
                )
              : FutureBuilder<Uint8List>(
                  future: content,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: ErrorNotice('${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final bytes = snapshot.data!, mime = file['mime'] as String;
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
                      child: Text(
                        client.tr(
                          '使用右上角按钮保存文件。',
                          'Use the download button to save this file.',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
