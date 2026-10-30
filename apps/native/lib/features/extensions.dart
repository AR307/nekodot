import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../ui/design.dart';

class ExtensionsPage extends StatefulWidget {
  final NekodotClient client;
  final String kind;
  const ExtensionsPage({super.key, required this.client, required this.kind});
  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  String query = '';
  int revision = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.kind == 'skills' ? 'Skills' : widget.client.tr('插件', 'Plugins'),
      ),
      actions: [
        IconButton(
          tooltip: widget.client.tr('导入', 'Import'),
          onPressed: () async {
            await pushPage(
              context,
              ExtensionInstall(client: widget.client, kind: widget.kind),
            );
            setState(() => revision++);
          },
          icon: const Icon(Icons.file_upload_outlined),
        ),
      ],
    ),
    body: AsyncPane(
      key: ValueKey(revision),
      load: () => widget.client.rpc('extensions.list', {'kind': widget.kind}),
      builder: (context, data, reload) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              onChanged: (value) => setState(() => query = value.toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.client.tr('搜索', 'Search'),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: objects(data['entries'])
                  .where(
                    (e) => '${e['name']} ${e['description']}'
                        .toLowerCase()
                        .contains(query),
                  )
                  .map(
                    (entry) => Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: ExtensionIcon(entry: entry),
                        title: Text('${entry['name']}'),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${entry['description']}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await pushPage(
                            context,
                            ExtensionPage(
                              client: widget.client,
                              entry: entry,
                              kind: widget.kind,
                            ),
                          );
                          reload();
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
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
          ? SvgPicture.memory(bytes, width: 40, height: 40)
          : Image.memory(bytes, width: 40, height: 40);
    }
    if (icon != null && icon.startsWith('https://')) {
      if (Uri.parse(icon).path.toLowerCase().endsWith('.svg')) {
        return SvgPicture.network(icon, width: 40, height: 40);
      }
      return Image.network(
        icon,
        width: 40,
        height: 40,
        errorBuilder: (context, error, stack) =>
            const Icon(Icons.extension_outlined, size: 36),
      );
    }
    if (icon != null && icon.runes.length <= 8) {
      return Text(icon, style: const TextStyle(fontSize: 32));
    }
    return Icon(
      entry['category'] == 'development'
          ? Icons.code
          : Icons.auto_awesome_outlined,
      color: accent,
      size: 36,
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${entry['name']}')),
    body: FutureBuilder<Json>(
      future: document,
      builder: (context, snapshot) {
        final data = snapshot.data ?? <String, dynamic>{};
        final repository = data['repository'] ?? entry['repository'];
        return ListView(
          key: PageStorageKey('extension-${entry['id']}'),
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                ExtensionIcon(entry: {...entry, ...data}),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '${entry['name']}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('${entry['source']} · ${entry['category']}'),
            const SizedBox(height: 12),
            Text('${entry['description']}'),
            if (repository is String)
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(repository),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: Text(repository),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(client.tr('没有提供仓库信息', 'No repository supplied')),
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
              child: Text(
                client.tr('选择 Bot 安装 / 管理', 'Install / manage for Bots'),
              ),
            ),
            const SizedBox(height: 24),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            if (snapshot.hasError) ...[
              ErrorNotice('${snapshot.error}'),
              TextButton(
                onPressed: () => setState(() {
                  document = load();
                }),
                child: Text(client.tr('重试', 'Retry')),
              ),
            ],
            if (snapshot.hasData && (data['content'] as String).isEmpty)
              Text(client.tr('未提供说明文件', 'No documentation supplied')),
            MarkdownBody(
              data: data['content'] as String? ?? '',
              selectable: true,
              onTapLink: (text, href, title) {
                if (href != null) {
                  launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            if ((data['content'] as String? ?? '').isNotEmpty)
              TextButton.icon(
                onPressed: () => pushPage(
                  context,
                  Scaffold(
                    appBar: AppBar(title: Text('${entry['name']}')),
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: MarkdownBody(
                        data: data['content'] as String,
                        selectable: true,
                        onTapLink: (text, href, title) {
                          if (href != null) {
                            launchUrl(
                              Uri.parse(href),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward),
                label: Text(client.tr('完整内容', 'Full content')),
              ),
            for (final path in data['files'] as List? ?? [])
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('$path'),
              ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(c.tr('安装与管理', 'Install & manage'))),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: identifier,
          decoration: InputDecoration(
            labelText: c.tr(
              '官方标识或 Git 仓库 / 技能路径',
              'Official identifier or Git repository / skill path',
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : () => upload(),
          icon: const Icon(Icons.upload_file),
          label: Text(c.tr('导入文件或 ZIP', 'Import file or ZIP')),
        ),
        if (Platform.isWindows)
          OutlinedButton.icon(
            onPressed: busy ? null : () => upload(directory: true),
            icon: const Icon(Icons.folder_open),
            label: Text(c.tr('导入完整目录', 'Import folder')),
          ),
        const SizedBox(height: 20),
        for (final bot in c.node.bots)
          CheckboxListTile(
            secondary: CatAvatar(color: '${bot['avatar']['color']}'),
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
        const SizedBox(height: 16),
        FilledButton(
          onPressed: target.isEmpty || busy
              ? null
              : () => run('extensions.install'),
          child: Text(c.tr('安装到所选 Bot', 'Install for selected Bots')),
        ),
        if (widget.entry != null)
          Wrap(
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
        if (operation != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: SelectableText(
              '${operation!['status']}\n${operation!['detail']}\n${operation!['results']}',
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (uploadProgress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(uploadProgress),
          ),
        ErrorNotice(error),
      ],
    ),
  );
}
