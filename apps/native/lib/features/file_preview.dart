import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../platform/file_actions.dart';
import '../ui/design.dart';
import 'bot_editor.dart';
import 'file_transfer.dart';
import 'svg_file_preview.dart';

class FileSelection {
  final Json file;
  final String nodeId;
  FileSelection(this.file, this.nodeId);
  String get key => '$nodeId:${file['fileId']}';
}

class FilePreviewScope extends InheritedWidget {
  final ValueChanged<FileSelection> onOpen;
  const FilePreviewScope({
    super.key,
    required this.onOpen,
    required super.child,
  });

  static void open(
    BuildContext context,
    NekodotClient client,
    FileSelection value,
  ) {
    final scope = context.getInheritedWidgetOfExactType<FilePreviewScope>();
    if (scope != null) {
      scope.onOpen(value);
    } else {
      pushPage(
        context,
        FilePage(
          key: ValueKey(value.key),
          client: client,
          file: value.file,
          nodeId: value.nodeId,
        ),
      );
    }
  }

  @override
  bool updateShouldNotify(FilePreviewScope oldWidget) =>
      onOpen != oldWidget.onOpen;
}

class FilePage extends StatefulWidget {
  final NekodotClient client;
  final Json file;
  final String nodeId;
  final bool embedded;
  final VoidCallback? onClose;
  const FilePage({
    super.key,
    required this.client,
    required this.file,
    required this.nodeId,
    this.embedded = false,
    this.onClose,
  });
  @override
  State<FilePage> createState() => _FilePageState();
}

class _FilePageState extends State<FilePage> {
  NekodotClient get client => widget.client;
  Json get file => widget.file;
  late Future<Uint8List> content;
  Future<String>? externalCopy;
  final transform = TransformationController();
  bool busy = false, source = false;
  double scale = 1;
  String error = '', notice = '';
  bool get svg => isSvgFile(file);
  bool get image => svg || '${file['mime']}'.startsWith('image/');
  bool get text =>
      '${file['mime']}'.startsWith('text/') ||
      file['mime'] == 'application/json';

  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    content = file['available'] == true
        ? downloadFile(client, '${file['fileId']}', nodeId: widget.nodeId)
        : Future.value(Uint8List(0));
    externalCopy = null;
    source = false;
    scale = 1;
    transform.value = Matrix4.identity();
    error = notice = '';
  }

  @override
  void didUpdateWidget(covariant FilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId ||
        oldWidget.file['fileId'] != file['fileId']) {
      load();
    }
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Future<String> copyForExternalApp() async {
    final bytes = await content;
    final root = await getTemporaryDirectory();
    final folder = await Directory('${root.path}/nekodot-preview')
        .create(recursive: true);
    final directory = await folder.createTemp('file-');
    final copy = File(
      '${directory.path}/${safeAttachmentName('${file['name']}')}',
    );
    await copy.writeAsBytes(bytes, flush: true);
    return copy.path;
  }

  Future<void> deliver(String action) async {
    setState(() {
      busy = true;
      error = notice = '';
    });
    try {
      if (action == 'open' || action == 'openWith' || action == 'reveal') {
        final path = await (externalCopy ??= copyForExternalApp());
        if (action == 'reveal') {
          await WindowsFileActions.invoke('reveal', path);
        } else {
          await openAttachment(path, chooseApp: action == 'openWith');
        }
      } else {
        final bytes = await content;
        if (action == 'share') {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(bytes, mimeType: file['mime'] as String)],
              fileNameOverrides: [safeAttachmentName('${file['name']}')],
            ),
          );
        } else {
          final saved = await FilePicker.saveFile(
            dialogTitle: client.tr('保存文件', 'Save file'),
            fileName: safeAttachmentName('${file['name']}'),
            mimeType: file['mime'] as String,
            bytes: bytes,
          );
          if (saved != null && mounted) {
            setState(() => notice = client.tr('文件已保存', 'File saved'));
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void zoom(double value) => setState(() {
    scale = value.clamp(.25, 4);
    transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  });

  Widget preview(Uint8List bytes) {
    if (source || text) {
      return SingleChildScrollView(
        key: const ValueKey('file-source'),
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: SelectableText(
            utf8.decode(bytes, allowMalformed: true),
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 12,
              height: 1.65,
            ),
          ),
        ),
      );
    }
    if (svg) return SvgFilePreview(bytes: bytes, scale: scale);
    if (image) {
      return ClipRect(
        child: InteractiveViewer(
          transformationController: transform,
          minScale: .25,
          maxScale: 4,
          child: Center(
            child: Image.memory(
              bytes,
              errorBuilder: (_, error, stack) => ErrorNotice('$error'),
            ),
          ),
        ),
      );
    }
    if (file['mime'] == 'application/pdf') {
      return PdfViewer.data(bytes, sourceName: '${file['name']}');
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 48, color: context.tone.ink3),
          const SizedBox(height: 12),
          Text(client.tr('使用其他应用查看此文件', 'Open this file in another app')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => deliver('open'),
            icon: const Icon(Icons.open_in_new),
            label: Text(client.tr('打开文件', 'Open file')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = file['available'] == true && !busy;
    return Scaffold(
      key: const ValueKey('file-preview'),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        flexibleSpace: const WindowDrag(),
        leading: IconButton(
          tooltip: client.tr('关闭预览', 'Close preview'),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
          icon: Icon(
            widget.embedded ? Icons.close : Icons.arrow_back,
            size: 20,
          ),
        ),
        titleSpacing: 0,
        title: Text(
          '${file['name']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        actions: [SizedBox(width: WindowChrome.reserved(context) + 12)],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  if (svg) ...[
                    TextButton(
                      onPressed: () => setState(() => source = false),
                      style: TextButton.styleFrom(
                        foregroundColor: source
                            ? context.tone.ink3
                            : context.tone.ink,
                      ),
                      child: Text(client.tr('预览', 'Preview')),
                    ),
                    TextButton(
                      onPressed: () => setState(() => source = true),
                      style: TextButton.styleFrom(
                        foregroundColor: source
                            ? context.tone.ink
                            : context.tone.ink3,
                      ),
                      child: Text(client.tr('源码', 'Source')),
                    ),
                  ] else
                    Text(
                      '${file['mime'] ?? ''}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: client.tr('保存文件', 'Save file'),
                    onPressed: available ? () => deliver('save') : null,
                    icon: const Icon(Icons.download_outlined, size: 20),
                  ),
                  PopupMenuButton<String>(
                    tooltip: client.tr('打开文件菜单', 'File actions'),
                    enabled: available,
                    onSelected: deliver,
                    icon: const Icon(Icons.open_in_new, size: 19),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'open',
                        child: Text(
                          client.tr('用系统默认应用打开', 'Open in default app'),
                        ),
                      ),
                      if (Platform.isWindows) ...[
                        PopupMenuItem(
                          value: 'openWith',
                          child: Text(client.tr('打开方式…', 'Open with…')),
                        ),
                        PopupMenuItem(
                          value: 'reveal',
                          child: Text(client.tr('在文件夹中显示', 'Show in folder')),
                        ),
                      ],
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'share',
                        child: Text(client.tr('分享文件', 'Share file')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
                padding: const EdgeInsets.all(12),
                child: ErrorNotice(error),
              ),
            if (notice.isNotEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(notice)),
            Expanded(
              child: file['available'] != true
                  ? Center(child: Text(client.tr('文件已不可用', 'File unavailable')))
                  : FutureBuilder<Uint8List>(
                      future: content,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: ErrorNotice('${snapshot.error}'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(child: ShiningText());
                        }
                        return preview(snapshot.data!);
                      },
                    ),
            ),
            if (image && !source)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: client.tr('缩小', 'Zoom out'),
                      onPressed: scale > .25 ? () => zoom(scale / 1.25) : null,
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(
                        '${(scale * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: client.tr('放大', 'Zoom in'),
                      onPressed: scale < 4 ? () => zoom(scale * 1.25) : null,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () => zoom(1),
                      icon: const Icon(Icons.fit_screen, size: 18),
                      label: Text(client.tr('适合窗口', 'Fit')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
