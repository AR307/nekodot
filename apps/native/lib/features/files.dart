import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/account.dart';
import '../platform/desktop.dart';
import '../platform/file_actions.dart';
import '../ui/design.dart';
import '../ui/message_markdown.dart';
import 'bot_editor.dart';
import 'office_preview.dart';

Future<Uint8List> downloadFile(
  NekodotClient c,
  String id, {
  String? targetNode,
}) async {
  final nodeId = targetNode ?? c.selectedNodeId, token = c.account.token;
  final cached = c.store?.file('files/$nodeId/$id');
  if (cached != null && await cached.exists()) return cached.readAsBytes();
  final response = await http
      .get(
        c.account.url('/api/nodes/$nodeId/files/$id'),
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(const Duration(minutes: 2));
  if (response.statusCode != 200) {
    throw RelayError('File HTTP ${response.statusCode}');
  }
  if (cached != null) {
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes(response.bodyBytes, flush: true);
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

/// A drawing rather than a bitmap: shown with the SVG renderer.
bool isSvg(Json file) =>
    '${file['mime']}'.split(';').first.trim().toLowerCase() ==
        'image/svg+xml' ||
    '${file['name']}'.toLowerCase().endsWith('.svg');

/// A file name Windows accepts for a copy handed to another app.
String safeFileName(String name) {
  var result = name
      .split(RegExp(r'[/\\]'))
      .last
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (result.isEmpty) return 'file';
  if (RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(result)) {
    result = '_$result';
  }
  if (result.length > 180) {
    final dot = result.lastIndexOf('.');
    final extension = dot > 0 && result.length - dot <= 20
        ? result.substring(dot)
        : '';
    result = '${result.substring(0, 180 - extension.length)}$extension';
  }
  return result;
}

String fileSize(num bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1048576
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1048576).toStringAsFixed(1)} MB';

IconData fileIcon(String name, String mime) {
  final format = officeFormat(name, mime);
  if (format != null) {
    return switch (format) {
      OfficeFormat.word => Icons.article_outlined,
      OfficeFormat.sheet => Icons.table_chart_outlined,
      OfficeFormat.slides => Icons.slideshow_outlined,
    };
  }
  if (mime.startsWith('image/') ||
      RegExp(
        r'\.(png|jpe?g|gif|webp|svg)$',
        caseSensitive: false,
      ).hasMatch(name)) {
    return Icons.image_outlined;
  }
  if (mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf')) {
    return Icons.picture_as_pdf_outlined;
  }
  return Icons.description_outlined;
}

Future<Json?> pickChatFile(
  NekodotClient client,
  String conversationId,
  ValueChanged<String> onProgress, {
  String? localPath,
  Uint8List? imageBytes,
  XFile? droppedFile,
  bool imageOnly = false,
}) async {
  final nodeId = client.selectedNodeId!;
  final file = localPath == null && imageBytes == null && droppedFile == null
      ? await FilePicker.pickFile(
          type: imageOnly ? FileType.image : FileType.any,
        )
      : null;
  if (file == null &&
      localPath == null &&
      imageBytes == null &&
      droppedFile == null) {
    return null;
  }
  final name =
      droppedFile?.name.split(RegExp(r'[/\\]')).last ??
      file?.name ??
      (localPath == null
          ? 'clipboard-${DateTime.now().millisecondsSinceEpoch}.png'
          : File(localPath).uri.pathSegments.last);
  final storage = client.store;
  if (storage == null) throw StateError('Local account storage is not ready');
  final target = storage.file('pending-files/${uid()}/${safeFileName(name)}');
  await target.parent.create(recursive: true);
  final bytes =
      droppedFile?.openRead() ??
      file?.readAsByteStream() ??
      (localPath == null
          ? Stream.value(imageBytes!)
          : File(localPath).openRead());
  final sink = target.openWrite();
  try {
    await sink.addStream(bytes);
  } finally {
    await sink.close();
  }
  return {
    'localPath': target.path,
    'name': name,
    'size': await target.length(),
    'nodeId': nodeId,
    'conversationId': conversationId,
    'mime':
        droppedFile?.mimeType ??
        (imageOnly || imageBytes != null
            ? 'image/png'
            : 'application/octet-stream'),
  };
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
        showFileViewer(context, widget.client, value);
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
          builder: (context, bytes) =>
              bytes.hasError ? row(value) : image(bytes.data, value),
        );
      }
      return row(value);
    },
  );

  Widget image(Uint8List? bytes, Json file) {
    final tone = context.tone, name = '${file['name']}';
    final placeholder = Container(
      width: 240,
      height: 160,
      decoration: ShapeDecoration(
        color: tone.bubble,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(12),
                  child: isSvg(file)
                      ? SvgPicture.memory(
                          bytes,
                          semanticsLabel: name,
                          placeholderBuilder: (_) => placeholder,
                          errorBuilder: (_, _, _) => row(file),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final density = MediaQuery.devicePixelRatioOf(
                              context,
                            );
                            return Image(
                              image: ResizeImage(
                                MemoryImage(bytes),
                                width: (constraints.maxWidth * density).ceil(),
                                height: (360 * density).ceil(),
                                policy: ResizeImagePolicy.fit,
                              ),
                              semanticLabel: name,
                              frameBuilder: (context, child, frame, sync) =>
                                  frame == null && !sync ? placeholder : child,
                            );
                          },
                        ),
                ),
              ),
            ),
    );
  }

  Widget row(Json? value) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    final corners = BorderRadius.circular(12);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: tone.bubble,
        shape: RoundedSuperellipseBorder(borderRadius: corners),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  value?['available'] == false
                      ? Icons.broken_image_outlined
                      : fileIcon(
                          '${value?['name'] ?? ''}',
                          '${value?['mime'] ?? ''}',
                        ),
                  size: 24,
                  color: tone.ink2,
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
                        maxLines: 1,
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
                    onTap: () => showFileViewer(context, widget.client, file),
                  ),
              ],
            ),
        ],
      );
    },
  );
}

/// The files open beside a conversation, one tab each.
class FileTabs extends StatelessWidget {
  final List<Json> files;
  final int at;
  final ValueChanged<int> onSelect, onClose;
  final String closeLabel;
  const FileTabs({
    super.key,
    required this.files,
    required this.at,
    required this.onSelect,
    required this.onClose,
    required this.closeLabel,
  });
  @override
  Widget build(BuildContext context) {
    final tone = context.tone, text = Theme.of(context).textTheme;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 8),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index], on = index == at;
                return InkWell(
                  key: ValueKey('file-tab-${file['fileId']}'),
                  onTap: () => onSelect(index),
                  child: Container(
                    padding: const EdgeInsets.only(left: 10, right: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: on ? tone.ink : tone.ink.withValues(alpha: 0),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          fileIcon('${file['name']}', '${file['mime']}'),
                          size: 18,
                          color: on ? tone.ink : tone.ink3,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            '${file['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: on ? tone.ink : tone.ink2,
                              fontWeight: on ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: closeLabel,
                          onPressed: () => onClose(index),
                          iconSize: 14,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.close, color: tone.ink3),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(width: WindowChrome.reserved(context)),
        ],
      ),
    );
  }
}

/// Routes workspace files to the shared right-hand reader.
class FilePreviewScope extends InheritedWidget {
  final ValueChanged<Json> open;
  const FilePreviewScope({super.key, required this.open, required super.child});
  @override
  bool updateShouldNotify(FilePreviewScope oldWidget) => false;
}

Future<void> showFileViewer(
  BuildContext context,
  NekodotClient client,
  Json file,
) async {
  final scope = context.getInheritedWidgetOfExactType<FilePreviewScope>();
  if (!context.tone.glass && scope != null) {
    scope.open(file);
    return;
  }
  if (context.tone.glass) {
    // On a phone it rises over what it was opened from; from there it can
    // take the whole screen.
    await openBottomSheet<void>(
      context,
      Builder(
        builder: (sheet) => FileViewer(
          client: client,
          file: file,
          onExpand: () {
            Navigator.pop(sheet);
            pushPage<void>(
              context,
              Scaffold(
                body: SafeArea(
                  child: FileViewer(client: client, file: file),
                ),
              ),
            );
          },
        ),
      ),
    );
    return;
  }
  // A file opened from a nested settings/library route still uses an in-app
  // right-hand reader, not a new window or a desktop full-page navigation.
  var expanded = false;
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: client.tr('关闭', 'Close'),
      barrierColor: Colors.black26,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      pageBuilder: (context, _, secondary) {
        return StatefulBuilder(
          builder: (context, setState) {
            final width = MediaQuery.sizeOf(context).width;
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: expanded ? width : width.clamp(0.0, 560.0),
                child: Material(
                  color: context.tone.base,
                  child: SafeArea(
                    child: FileViewer(
                      client: client,
                      file: file,
                      expanded: expanded,
                      onExpand: () => setState(() => expanded = !expanded),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionsBuilder: (context, animation, secondary, child) =>
          SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                ),
            child: child,
          ),
    ),
  );
}

class FileViewer extends StatefulWidget {
  final NekodotClient client;
  final Json file;
  final VoidCallback? onClose, onExpand;
  final bool expanded;

  /// Whether its name is already on a tab above it; its bar then says how
  /// large the file is.
  final bool tabbed;
  const FileViewer({
    super.key,
    required this.client,
    required this.file,
    this.onClose,
    this.onExpand,
    this.expanded = false,
    this.tabbed = false,
  });
  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  NekodotClient get client => widget.client;
  Json get file => widget.file;
  late final content = downloadFile(client, file['fileId'] as String);
  final readingScroll = ScrollController();
  @override
  void dispose() {
    readingScroll.dispose();
    super.dispose();
  }

  bool busy = false, source = false;
  String error = '', notice = '';
  Future<String>? copy;

  /// A copy in a folder of its own, for another app to open.
  Future<String> copyForApps() async {
    final bytes = await content;
    final root = await getTemporaryDirectory();
    final separator = Platform.pathSeparator;
    final folder = await Directory('${root.path}${separator}nekodot-files')
        .create(recursive: true);
    final directory = await folder.createTemp('file-');
    // The Windows shell takes only its own separator.
    final path = '${directory.path}$separator${safeFileName('${file['name']}')}'
        .replaceAll('/', separator);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Hands the file to the system: its default app, the Windows "Open with"
  /// list, or its folder.
  Future<void> openOutside(String action) async {
    setState(() {
      busy = true;
      error = '';
      notice = '';
    });
    try {
      final path = await (copy ??= copyForApps());
      if (action == 'reveal') {
        await WindowsFileActions.invoke('reveal', path);
      } else {
        await openAttachment(path, chooseApp: action == 'openWith');
      }
    } on PlatformException catch (e) {
      copy = null;
      final message = e.code == 'blocked_type'
          ? client.tr(
              '程序和脚本不能直接打开',
              "Programs and scripts can't be opened directly",
            )
          : e.message ?? e.code;
      if (mounted) setState(() => error = message);
    } catch (e) {
      copy = null;
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget fileMenu(bool enabled) => ActionMenu<String>(
    key: const ValueKey('viewer-open'),
    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
    alignEnd: true,
    width: 300,
    enabled: enabled,
    items: [
      MenuAction(
        value: 'share',
        icon: Icons.ios_share_outlined,
        label: client.tr('分享文件', 'Share file'),
      ),
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
        MenuAction(
          key: const ValueKey('open-default'),
          value: 'open',
          icon: Icons.open_in_new,
          label: client.tr('用默认应用打开', 'Open in default app'),
        ),
        if (Platform.isWindows) ...[
          MenuAction(
            key: const ValueKey('open-with'),
            value: 'openWith',
            icon: Icons.apps_outlined,
            label: client.tr('打开方式…', 'Open with…'),
          ),
          MenuAction(
            key: const ValueKey('open-folder'),
            value: 'reveal',
            icon: Icons.folder_open_outlined,
            label: client.tr('在文件夹中显示', 'Show in folder'),
          ),
        ],
      ],
    ],
    onSelected: (action) async {
      if (action == 'share') {
        await deliver(share: true);
      } else {
        await openOutside(action);
      }
    },
  );

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
  Widget build(BuildContext context) {
    final tone = context.tone;
    final available = file['available'] == true, svg = isSvg(file);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              if (widget.tabbed)
                Expanded(
                  child: Text(
                    file['size'] is num ? fileSize(file['size'] as num) : '',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tone.ink3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              else ...[
                Icon(
                  fileIcon('${file['name']}', '${file['mime']}'),
                  size: 20,
                  color: tone.ink3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: '${file['name']}',
                    child: Text(
                      '${file['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              if (RegExp(r'\.(tar\.gz|tgz)$').hasMatch('${file['name']}') &&
                  available)
                IconButton(
                  tooltip: client.tr('作为新 Bot 导入', 'Import as a new Bot'),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      navigator.pop();
                    }
                    pushPage(
                      navigator.context,
                      BotEditor(
                        client: client,
                        importProfile: true,
                        initialArchive: file,
                      ),
                    );
                  },
                ),
              if (svg && available)
                IconButton(
                  key: const ValueKey('viewer-svg-source'),
                  tooltip: source
                      ? client.tr('查看图片', 'Show picture')
                      : client.tr('查看源码', 'Show source'),
                  onPressed: () => setState(() => source = !source),
                  icon: Icon(source ? Icons.image_outlined : Icons.code),
                ),
              if (tone.glass)
                IconButton(
                  tooltip: client.tr('分享文件', 'Share file'),
                  onPressed: available && !busy
                      ? () => deliver(share: true)
                      : null,
                  icon: const Icon(Icons.ios_share_outlined),
                )
              else
                fileMenu(available && !busy),
              IconButton(
                tooltip: client.tr('保存文件', 'Save file'),
                onPressed: available && !busy
                    ? () => deliver(share: false)
                    : null,
                icon: const Icon(Icons.download_outlined),
              ),
              if (widget.onExpand != null)
                IconButton(
                  key: const ValueKey('viewer-expand'),
                  tooltip: widget.expanded
                      ? client.tr('收起', 'Collapse')
                      : client.tr('展开', 'Expand'),
                  onPressed: widget.onExpand,
                  icon: Icon(
                    widget.expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                ),
              IconButton(
                tooltip: client.tr('关闭', 'Close'),
                onPressed: widget.onClose ?? () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
              SizedBox(width: WindowChrome.reserved(context)),
            ],
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
            child: Text(
              notice,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: tone.bubble,
            child: !available
                ? Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: tone.ink3,
                    ),
                  )
                : FutureBuilder<Uint8List>(
                    future: content,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: ErrorNotice('${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: ShiningText());
                      }
                      final bytes = snapshot.data!,
                          mime = file['mime'] as String;
                      final office = officeFormat('${file['name']}', mime);
                      if (office != null) {
                        return OfficePreview(
                          key: ValueKey(file['fileId']),
                          bytes: bytes,
                          format: office,
                          zoomInLabel: client.tr('放大', 'Zoom in'),
                          zoomOutLabel: client.tr('缩小', 'Zoom out'),
                        );
                      }
                      if (svg && !source) {
                        return InteractiveViewer(
                          key: const ValueKey('viewer-svg'),
                          minScale: .25,
                          maxScale: 4,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: SvgPicture.memory(
                                bytes,
                                semanticsLabel: '${file['name']}',
                                errorBuilder: (_, e, _) => ErrorNotice('$e'),
                              ),
                            ),
                          ),
                        );
                      }
                      if (mime.startsWith('image/') && !svg) {
                        return InteractiveViewer(
                          key: const ValueKey('viewer-image'),
                          maxScale: 6,
                          child: Center(
                            child: Image.memory(
                              bytes,
                              semanticLabel: '${file['name']}',
                            ),
                          ),
                        );
                      }
                      if (mime == 'application/pdf') {
                        return PdfViewer.data(
                          bytes,
                          sourceName: file['name'] as String,
                        );
                      }
                      final markdown =
                          mime == 'text/markdown' ||
                          RegExp(
                            r'\.(md|markdown)$',
                            caseSensitive: false,
                          ).hasMatch('${file['name']}');
                      if (svg ||
                          markdown ||
                          mime.startsWith('text/') ||
                          mime == 'application/json') {
                        return ColoredBox(
                          color: tone.surface,
                          child: SingleChildScrollView(
                            key: const ValueKey('viewer-reading-scroll'),
                            controller: readingScroll,
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 720,
                                ),
                                child: markdown
                                    ? MessageMarkdown(
                                        key: const ValueKey('viewer-markdown'),
                                        data: utf8.decode(
                                          bytes,
                                          allowMalformed: true,
                                        ),
                                      )
                                    : SelectableText(
                                        utf8.decode(
                                          bytes,
                                          allowMalformed: true,
                                        ),
                                        key: const ValueKey('viewer-text'),
                                      ),
                              ),
                            ),
                          ),
                        );
                      }
                      return Center(
                        child: Icon(
                          Icons.description_outlined,
                          size: 48,
                          color: tone.ink3,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
