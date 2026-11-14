import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/account.dart';
import '../ui/design.dart';
import 'plugin_catalog.dart';

class ExtensionsBody extends StatefulWidget {
  final NekodotClient client;
  final String kind;
  const ExtensionsBody({super.key, required this.client, required this.kind});
  @override
  State<ExtensionsBody> createState() => _ExtensionsBodyState();
}

class _ExtensionsBodyState extends State<ExtensionsBody> {
  String get kind => widget.kind;
  final search = TextEditingController();
  final scroll = ScrollController();
  String query = '';
  bool installedOnly = false;
  String category = '';
  late Future<Json> listing = load();
  Future<Json> load() => widget.client.rpc('extensions.list', {'kind': kind});
  void reload() => setState(() {
    listing = load();
  });
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return FutureBuilder<Json>(
      future: listing,
      builder: (context, snapshot) {
        final all = objects(snapshot.data?['entries']);
        final categories = all.map((e) => '${e['category']}').toSet().toList()
          ..sort();
        final entries = all
            .where(
              (e) => '${e['name']} ${e['description']}'.toLowerCase().contains(
                query,
              ),
            )
            .where((e) => category.isEmpty || e['category'] == category)
            .where(
              (e) =>
                  !installedOnly ||
                  objects(e['states']).any((s) => s['installed'] == true),
            )
            .toList();
        Widget tile(Json entry, bool wide) => PluginTile(
          key: ValueKey('extension-${entry['id']}'),
          wide: wide,
          icon: ExtensionIcon(entry: entry),
          name: '${entry['name']}',
          description: '${entry['description']}',
          status: Row(
            children: [
              for (final bot
                  in c.node.bots
                      .where(
                        (bot) =>
                            objects(entry['states'])
                                .any((state) => state['botId'] == bot['botId']),
                      )
                      .take(3))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CatAvatar.of(bot, size: 20),
                ),
              if (objects(entry['states']).isNotEmpty) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  objects(entry['states']).isNotEmpty
                      ? '${c.tr('已安装', 'Installed')} ${objects(entry['states']).length}'
                      : '${entry['category']}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          onTap: () async {
            await pushPage(
              context,
              ExtensionPage(client: c, entry: entry, kind: kind),
            );
            if (mounted) reload();
          },
        );
        return PluginCatalog(
          scroll: scroll,
          count: entries.length,
          loading: snapshot.connectionState == ConnectionState.waiting,
          search: TextField(
            key: ValueKey('extension-search-$kind'),
            controller: search,
            onChanged: (value) => setState(() => query = value.toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Symbols.search, size: 20),
              hintText: c.tr('搜索', 'Search'),
            ),
          ),
          actions: [
            IconAction(
              icon: Symbols.refresh,
              tooltip: c.tr('刷新', 'Refresh'),
              onPressed: reload,
            ),
            IconAction(
              icon: Symbols.add,
              tooltip: c.tr('导入', 'Import'),
              onPressed: !c.online
                  ? null
                  : () async {
                      await pushPage(
                        context,
                        ExtensionInstall(client: c, kind: kind),
                      );
                      if (mounted) reload();
                    },
            ),
          ],
          filters: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Segment<bool>(
                value: installedOnly,
                options: {
                  false: Text(c.tr('全部', 'All')),
                  true: Text(c.tr('已安装', 'Installed')),
                },
                onChanged: (value) => setState(() => installedOnly = value),
              ),
              ActionMenu<String>(
                tooltip: c.tr('全部', 'All'),
                items: [
                  for (final value in ['', ...categories])
                    MenuAction(
                      value: value,
                      label: value.isEmpty ? c.tr('全部', 'All') : value,
                      selected: category == value,
                    ),
                ],
                onSelected: (value) => setState(() => category = value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(category.isEmpty ? c.tr('全部', 'All') : category),
                        const SizedBox(width: 8),
                        const Icon(Symbols.expand_more, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          notice: snapshot.hasError
              ? ErrorNotice(
                  c.tr('请求失败，请重试', 'Request failed. Try again.'),
                  action: TextButton(
                    onPressed: reload,
                    child: Text(c.tr('重试', 'Retry')),
                  ),
                )
              : null,
          empty: snapshot.hasError
              ? null
              : Text(
                  c.tr('未找到插件', 'No plugins found'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          itemBuilder: (index, wide) => tile(entries[index], wide),
        );
      },
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
          ? SvgPicture.memory(bytes, width: 24, height: 24)
          : Image.memory(bytes, width: 24, height: 24);
    }
    if (icon != null && icon.startsWith('https://')) {
      if (Uri.parse(icon).path.toLowerCase().endsWith('.svg')) {
        return SvgPicture.network(icon, width: 24, height: 24);
      }
      return Image.network(
        icon,
        width: 24,
        height: 24,
        errorBuilder: (context, error, stack) =>
            const Icon(Symbols.extension, size: 32),
      );
    }
    if (icon != null && icon.runes.length <= 8) {
      return Text(icon, style: const TextStyle(fontSize: 20));
    }
    return Icon(
      entry['category'] == 'development' ? Symbols.code : Symbols.auto_awesome,
      color: context.tone.ink2,
      size: 24,
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
  late Json entry = widget.entry;
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
          maxWidth: 720,
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
                      const SizedBox(height: 8),
                      Text('${entry['category']}', style: text.bodySmall),
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
                  icon: const Icon(Symbols.open_in_new, size: 16),
                  label: Text(repository),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
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
                    final listing = await client.rpc('extensions.list', {
                      'kind': widget.kind,
                    });
                    if (!mounted) return;
                    setState(() {
                      entry = objects(listing['entries'])
                          .firstWhere((e) => e['id'] == entry['id']);
                      document = load();
                    });
                  }
                },
                child: Text(
                  objects(entry['states']).isEmpty
                      ? client.tr('安装', 'Install')
                      : client.tr('管理', 'Manage'),
                ),
              ),
            ),
            if (objects(entry['states']).isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionLabel(client.tr('已安装', 'Installed')),
              for (final bot in client.node.bots.where(
                (bot) =>
                    objects(entry['states'])
                        .any((state) => state['botId'] == bot['botId']),
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CatAvatar.of(bot, size: 28),
                  title: Text('${bot['displayName']}'),
                  trailing: Icon(
                    objects(entry['states']).any(
                          (state) =>
                              state['botId'] == bot['botId'] &&
                              state['enabled'] == true,
                        )
                        ? Symbols.check_circle
                        : Symbols.pause_circle,
                    size: 18,
                  ),
                ),
            ],
            const SizedBox(height: 24),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: ShiningText()),
            if (snapshot.hasError) ...[
              ErrorNotice('${snapshot.error}'),
              Center(
                child: IconButton(
                  tooltip: client.tr('重试', 'Retry'),
                  onPressed: () => setState(() {
                    document = load();
                  }),
                  icon: const Icon(Symbols.refresh),
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
                  icon: const Icon(Symbols.arrow_forward, size: 16),
                  label: Text(client.tr('完整内容', 'Full content')),
                ),
              ),
            if ((data['files'] as List? ?? []).isNotEmpty) ...[
              SectionLabel(client.tr('文件', 'Files')),
              Column(
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
  final installed = <String>{};
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
    installed.addAll(
      objects(widget.entry?['states'])
          .where((state) => state['installed'] == true)
          .map((state) => '${state['botId']}'),
    );
    target.addAll(installed);
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
          final url = c.account
              .url('/api/nodes/${c.selectedNodeId}/imports/$importId')
              .replace(
                queryParameters: {'path': file.name, 'offset': '$offset'},
              );
          final response = await http.put(
            url,
            headers: {
              'Authorization': 'Bearer ${c.account.token}',
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
                  '${files.indexOf(file) + 1}/${files.length}  ${file.name}',
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
    setState(() {
      busy = true;
      error = '';
    });
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
            if (mounted) {
              setState(() {
                busy = false;
                if (method == 'extensions.install') {
                  installed.addAll(
                    objects(value['results'])
                        .where((row) => row['ok'] == true)
                        .map((row) => '${row['botId']}'),
                  );
                }
              });
            }
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
    title:
        widget.entry?['name'] as String? ?? c.tr('安装与管理', 'Install & manage'),
    actions: [
      IconButton(
        tooltip: c.tr('导入文件或 ZIP', 'Import file or ZIP'),
        onPressed: busy ? null : () => upload(),
        icon: const Icon(Symbols.upload_file),
      ),
      if (!Platform.isAndroid)
        IconButton(
          tooltip: c.tr('导入完整目录', 'Import folder'),
          onPressed: busy ? null : () => upload(directory: true),
          icon: const Icon(Symbols.folder_open),
        ),
    ],
    body: PageList(
      children: [
        if (widget.entry == null || identifier.text.isNotEmpty)
          LabeledField(
            label: c.tr('标识或 Git 仓库', 'Identifier or Git repository'),
            child: TextField(
              controller: identifier,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(),
            ),
          ),
        const SizedBox(height: 14),
        Column(
          children: [
            for (final bot in c.node.bots)
              CheckboxListTile(
                secondary: CatAvatar.of(bot),
                title: Text('${bot['displayName']}'),
                subtitle: Text(
                  installed.contains(bot['botId'])
                      ? c.tr('已安装', 'Installed')
                      : c.tr('未安装', 'Not installed'),
                ),
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
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (widget.entry == null || identifier.text.isNotEmpty)
              FilledButton(
                onPressed:
                    target.isEmpty || busy || identifier.text.trim().isEmpty
                    ? null
                    : () => run('extensions.install'),
                child: Text(c.tr('安装', 'Install')),
              ),
            if (widget.entry != null)
              TextButton(
                onPressed:
                    target.isEmpty || busy || !target.every(installed.contains)
                    ? null
                    : () => run('extensions.toggle', true),
                child: Text(c.tr('启用', 'Enable')),
              ),
            if (widget.entry != null)
              TextButton(
                onPressed:
                    target.isEmpty || busy || !target.every(installed.contains)
                    ? null
                    : () => run('extensions.toggle', false),
                child: Text(c.tr('停用', 'Disable')),
              ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: ShiningText()),
          ),
        if (operation != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final result in objects(operation!['results']))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: Icon(
                      result['ok'] == true
                          ? Symbols.check_circle
                          : Symbols.error,
                      size: 20,
                    ),
                    title: Text(
                      '${c.node.bots.where((bot) => bot['botId'] == result['botId']).firstOrNull?['displayName'] ?? result['botId']}',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SelectableText(
                            '${result['detail']}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
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
