import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../platform/desktop.dart';
import '../ui/design.dart';

Future<void> showExtensionsDialog(BuildContext context, NekodotClient client) =>
    showDialog(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(40),
        child: SizedBox(
          width: 900,
          height: 700,
          child: ExtensionsPage(client: client, kind: 'skills', dialog: true),
        ),
      ),
    );

class ExtensionsPage extends StatefulWidget {
  final NekodotClient client;
  final String kind;
  final bool dialog;
  const ExtensionsPage({
    super.key,
    required this.client,
    required this.kind,
    this.dialog = false,
  });
  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  late String kind = widget.kind;
  String query = '';
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final glass = context.tone.glass;
    return Scaffold(
      extendBodyBehindAppBar: glass,
      appBar: AppBar(
        flexibleSpace: glass ? const Frost() : const WindowDrag(),
        automaticallyImplyLeading: !widget.dialog,
        titleSpacing: widget.dialog ? 20 : 0,
        title: glass
            ? Text(kind == 'skills' ? 'Skills' : c.tr('插件', 'Plugins'))
            : Segment<String>(
                value: kind,
                options: {
                  'skills': const Text('Skills'),
                  'plugins': Text(c.tr('插件', 'Plugins')),
                },
                onChanged: (value) => setState(() => kind = value),
              ),
        actions: [
          RoundButton(
            tooltip: c.tr('导入', 'Import'),
            icon: Icons.add_rounded,
            onPressed: () async {
              await pushPage(context, ExtensionInstall(client: c, kind: kind));
              setState(() => revision++);
            },
          ),
          if (widget.dialog) ...[
            const SizedBox(width: 8),
            RoundButton(
              tooltip: c.tr('关闭', 'Close'),
              icon: Icons.close_rounded,
              onPressed: () => Navigator.pop(context),
            ),
          ],
          const SizedBox(width: 12),
          if (!widget.dialog) SizedBox(width: WindowChrome.reserved(context)),
        ],
      ),
      body: AsyncPane(
        key: ValueKey('$kind:$revision'),
        load: () => c.rpc('extensions.list', {'kind': kind}),
        builder: (context, data, reload) {
          final entries = objects(data['entries'])
              .where(
                (e) => '${e['name']} ${e['description']}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList();
          Widget tile(Json entry) => ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: entry['icon'] == null ? null : ExtensionIcon(entry: entry),
            title: Text(
              '${entry['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${entry['description']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () async {
              await pushPage(
                context,
                ExtensionPage(client: c, entry: entry, kind: kind),
              );
              reload();
            },
          );
          if (glass) {
            return PageList(
              children: [
                TextField(
                  onChanged: (value) =>
                      setState(() => query = value.toLowerCase()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: c.tr('搜索', 'Search'),
                  ),
                ),
                const SizedBox(height: 14),
                PanelGroup(children: entries.map(tile).toList()),
              ],
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 2 : 1;
              final rows = (entries.length / columns).ceil();
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  14,
                  8,
                  14,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                itemCount: rows + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => query = value.toLowerCase()),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: c.tr('搜索', 'Search'),
                        ),
                      ),
                    );
                  }
                  final at = (index - 1) * columns;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = at; i < at + columns; i++)
                        Expanded(
                          child: i < entries.length
                              ? tile(entries[i])
                              : const SizedBox.shrink(),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class ExtensionIcon extends StatelessWidget {
  final Json entry;
  const ExtensionIcon({super.key, required this.entry});
  @override
  Widget build(BuildContext context) {
    final icon = entry['icon'] as String?;
    if (icon != null && icon.startsWith('data:image/')) {
      final data = UriData.parse(icon);
      final bytes = data.contentAsBytes();
      return data.mimeType == 'image/svg+xml'
          ? SvgPicture.memory(bytes, width: 36, height: 36)
          : Image.memory(bytes, width: 36, height: 36);
    }
    if (icon != null && icon.startsWith('https://')) {
      if (Uri.parse(icon).path.toLowerCase().endsWith('.svg')) {
        return SvgPicture.network(icon, width: 36, height: 36);
      }
      return Image.network(
        icon,
        width: 36,
        height: 36,
        errorBuilder: (context, error, stack) =>
            const Icon(Icons.extension_rounded, size: 32),
      );
    }
    if (icon != null && icon.runes.length <= 8) {
      return Text(icon, style: const TextStyle(fontSize: 32));
    }
    return Icon(
      entry['category'] == 'development'
          ? Icons.code_rounded
          : Icons.auto_awesome_rounded,
      color: context.tone.ink2,
      size: 32,
    );
  }
}

class ExtensionPage extends StatefulWidget {
  final NekodotClient client;
  final Json entry;
  final String kind;
  const ExtensionPage({
    super.key,
    required this.client,
    required this.entry,
    required this.kind,
  });
  @override
  State<ExtensionPage> createState() => _ExtensionPageState();
}

class _ExtensionPageState extends State<ExtensionPage> {
  Json get entry => widget.entry;
  NekodotClient get client => widget.client;
  late Future<Json> document = load();
  Future<Json> load() {
    final installed = objects(entry['states'])
        .where((s) => s['installed'] == true)
        .firstOrNull;
    return client.rpc('extensions.content', {
      'kind': widget.kind,
      'name': entry['id'],
      if (installed != null) 'botId': installed['botId'],
      if (installed == null && entry['identifier'] != null)
        'identifier': entry['identifier'],
    });
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '${entry['name']}',
    body: FutureBuilder<Json>(
      future: document,
      builder: (context, snapshot) {
        final data = snapshot.data ?? <String, dynamic>{};
        final repository = data['repository'] ?? entry['repository'];
        final text = Theme.of(context).textTheme;
        void openLink(String text, String? href, String title) {
          if (href != null) {
            launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
          }
        }

        return PageList(
          key: PageStorageKey('extension-${entry['id']}'),
          children: [
            Row(
              children: [
                ExtensionIcon(entry: {...entry, ...data}),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry['description']}', style: text.bodyMedium),
                      Text(
                        '${entry['source']} · ${entry['category']}',
                        style: text.labelMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (repository is String)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(repository),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(repository),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                await pushPage(
                  context,
                  ExtensionInstall(
                    client: client,
                    kind: widget.kind,
                    entry: entry,
                  ),
                );
                if (mounted) {
                  setState(() {
                    document = load();
                  });
                }
              },
              child: Text(client.tr('安装 / 管理', 'Install / manage')),
            ),
            const SizedBox(height: 20),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: Breathing()),
            if (snapshot.hasError) ...[
              ErrorNotice('${snapshot.error}'),
              Center(
                child: IconButton(
                  tooltip: client.tr('重试', 'Retry'),
                  onPressed: () => setState(() {
                    document = load();
                  }),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ],
            MarkdownBody(
              data: data['content'] as String? ?? '',
              selectable: true,
              styleSheet: markdownStyle(context),
              onTapLink: openLink,
            ),
            const SizedBox(height: 12),
            if ((data['content'] as String? ?? '').isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => pushPage(
                    context,
                    AppPage(
                      title: '${entry['name']}',
                      body: PageList(
                        maxWidth: 760,
                        children: [
                          MarkdownBody(
                            data: data['content'] as String,
                            selectable: true,
                            styleSheet: markdownStyle(context),
                            onTapLink: openLink,
                          ),
                        ],
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(client.tr('完整内容', 'Full content')),
                ),
              ),
            if ((data['files'] as List? ?? []).isNotEmpty) ...[
              SectionLabel(client.tr('文件', 'Files')),
              PanelGroup(
                children: [
                  for (final path in data['files'] as List)
                    ListTile(
                      dense: true,
                      title: Text(
                        '$path',
                        style: const TextStyle(
                          fontFamily: monoFont,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}

class ExtensionInstall extends StatefulWidget {
  final NekodotClient client;
  final String kind;
  final Json? entry;
  const ExtensionInstall({
    super.key,
    required this.client,
    required this.kind,
    this.entry,
  });
  @override
  State<ExtensionInstall> createState() => _ExtensionInstallState();
}

class _ExtensionInstallState extends State<ExtensionInstall> {
  final target = <String>{}, identifier = TextEditingController();
  Json? operation;
  String error = '';
  bool busy = false;
  Timer? timer;
  String? importId;
  String uploadProgress = '';
  NekodotClient get c => widget.client;
  @override
  void initState() {
    super.initState();
    identifier.text = widget.entry?['identifier'] as String? ?? '';
  }

  @override
  void dispose() {
    identifier.dispose();
    timer?.cancel();
    super.dispose();
  }

  Future<void> upload({bool directory = false}) async {
    try {
      final files = <({String name, Future<List<int>> Function() read})>[];
      String label;
      if (directory) {
        final path = await FilePicker.getDirectoryPath();
        if (path == null) return;
        final root = Directory(path);
        label = root.uri.pathSegments.where((s) => s.isNotEmpty).last;
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          final relative = entity.path
              .substring(root.path.length + 1)
              .replaceAll('\\', '/');
          if (entity is File && !relative.split('/').contains('.git')) {
            files.add((name: relative, read: entity.readAsBytes));
          }
        }
      } else {
        final file = await FilePicker.pickFile();
        if (file == null) return;
        label = file.name;
        files.add((name: file.name, read: file.readAsBytes));
      }
      if (files.isEmpty) throw RelayError(c.tr('目录为空', 'The folder is empty'));
      final created = await c.rpc('imports.create');
      importId = created['importId'] as String;
      setState(() => busy = true);
      for (final file in files) {
        final bytes = await file.read();
        for (
          var offset = 0;
          offset < bytes.length || offset == 0;
          offset += 196608
        ) {
          final end = (offset + 196608).clamp(0, bytes.length);
          final url = c
              .url('/api/nodes/${c.selectedNodeId}/imports/$importId')
              .replace(
                queryParameters: {'path': file.name, 'offset': '$offset'},
              );
          final response = await http.put(
            url,
            headers: {
              'Authorization': 'Bearer ${c.token}',
              'Content-Type': 'application/octet-stream',
            },
            body: bytes.sublist(offset, end),
          );
          if (response.statusCode != 200) {
            throw RelayError('Upload HTTP ${response.statusCode}');
          }
          if (mounted) {
            setState(
              () => uploadProgress =
                  '${files.indexOf(file) + 1}/${files.length} · ${file.name}',
            );
          }
        }
      }
      if (mounted) {
        setState(() {
          error = '';
          identifier.text = label;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> run(String method, [bool? enabled]) async {
    setState(() => busy = true);
    try {
      final result = await c.rpc(method, {
        'kind': widget.kind,
        'botIds': target.toList(),
        if (method == 'extensions.install') ...{
          if (importId != null)
            'importId': importId
          else
            'identifier': identifier.text,
        } else ...{
          'name': widget.entry!['id'],
          'enabled': enabled,
        },
      });
      if (!mounted) return;
      setState(() => operation = result);
      timer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final value = await c.rpc('operations.get', {
            'operationId': operation!['operationId'],
          });
          if (mounted) setState(() => operation = value);
          if (value['status'] != 'running') {
            timer?.cancel();
            if (mounted) setState(() => busy = false);
          }
        } catch (e) {
          timer?.cancel();
          if (mounted) {
            setState(() {
              error = '$e';
              busy = false;
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: c.tr('安装与管理', 'Install & manage'),
    actions: [
      IconButton(
        tooltip: c.tr('导入文件或 ZIP', 'Import file or ZIP'),
        onPressed: busy ? null : () => upload(),
        icon: const Icon(Icons.upload_file_rounded),
      ),
      if (Platform.isWindows)
        IconButton(
          tooltip: c.tr('导入完整目录', 'Import folder'),
          onPressed: busy ? null : () => upload(directory: true),
          icon: const Icon(Icons.folder_open_rounded),
        ),
    ],
    body: PageList(
      children: [
        TextField(
          controller: identifier,
          decoration: InputDecoration(
            labelText: c.tr('标识或 Git 仓库', 'Identifier or Git repository'),
          ),
        ),
        const SizedBox(height: 14),
        PanelGroup(
          children: [
            for (final bot in c.node.bots)
              CheckboxListTile(
                secondary: CatAvatar.of(bot),
                title: Text('${bot['displayName']}'),
                value: target.contains(bot['botId']),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          target.add(bot['botId'] as String);
                        } else {
                          target.remove(bot['botId']);
                        }
                      }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: target.isEmpty || busy
              ? null
              : () => run('extensions.install'),
          child: Text(c.tr('安装', 'Install')),
        ),
        if (widget.entry != null)
          Center(
            child: Wrap(
              spacing: 10,
              children: [
                TextButton(
                  onPressed: target.isEmpty || busy
                      ? null
                      : () => run('extensions.toggle', true),
                  child: Text(c.tr('启用', 'Enable')),
                ),
                TextButton(
                  onPressed: target.isEmpty || busy
                      ? null
                      : () => run('extensions.toggle', false),
                  child: Text(c.tr('停用', 'Disable')),
                ),
              ],
            ),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Breathing()),
          ),
        if (operation != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SelectableText(
              '${operation!['status']}\n${operation!['detail']}\n${operation!['results']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (uploadProgress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              uploadProgress,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ErrorNotice(error),
      ],
    ),
  );
}
