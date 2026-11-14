import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../data/spaces.dart';
import '../ui/design.dart';
import '../platform/desktop.dart';
import 'files.dart';
import 'space_mark.dart';
import 'space_webview.dart';

class SpaceScope extends InheritedWidget {
  final ValueChanged<Space> open;
  const SpaceScope({super.key, required this.open, required super.child});
  @override
  bool updateShouldNotify(SpaceScope oldWidget) => open != oldWidget.open;
}

void openSpace(BuildContext context, NekodotClient c, Space space) {
  final scope = context.getInheritedWidgetOfExactType<SpaceScope>();
  if (scope != null && MediaQuery.sizeOf(context).width >= 840) {
    scope.open(space);
  } else {
    pushPage(
      context,
      SpacePage(client: c, nodeId: c.selectedNodeId!, spaceId: space.spaceId),
    );
  }
}

class SpaceCard extends StatelessWidget {
  final NekodotClient client;
  final String spaceId;
  const SpaceCard({super.key, required this.client, required this.spaceId});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: client.node,
    builder: (context, _) {
      final space = client.node.spaces[spaceId];
      if (space == null) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: context.tone.raised,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: SpaceMark(space: space, size: 32),
              title: Text(
                space.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Symbols.open_in_new, size: 18),
              onTap: () => openSpace(context, client, space),
            ),
          ),
        ),
      );
    },
  );
}

class SpacePage extends StatefulWidget {
  final NekodotClient client;
  final String nodeId, spaceId;
  final bool embedded, expanded;
  final VoidCallback? onExpand;

  /// Where its back button leads when it was opened from the gallery.
  final VoidCallback? onBack;
  const SpacePage({
    super.key,
    required this.client,
    required this.nodeId,
    required this.spaceId,
    this.embedded = false,
    this.expanded = false,
    this.onExpand,
    this.onBack,
  });
  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  NekodotClient get c => widget.client;
  late final storage = c.store!;
  Space? loaded;
  SpaceBundle? bundle;
  WebViewEnvironment? environment;
  bool busy = true,
      failed = false,
      missingRuntime = false,
      notDownloaded = false;

  /// The site has drawn itself. Until then its last picture stands in.
  bool live = false;
  int generation = 0;
  Space? get current => c.nodes[widget.nodeId]?.spaces[widget.spaceId];
  String get cacheKey => 'spaces/open/${widget.nodeId}/${widget.spaceId}';
  bool get supported => Platform.isWindows || Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    // Flutter unmounts the child WebView before this parent state.
    unawaited(environment?.dispose());
    // It has been open, so what its tile shows is due again. Said once the
    // tree has settled: the gallery listens.
    if (loaded != null) {
      final thumbs = c.spaces.thumbs,
          nodeId = widget.nodeId,
          spaceId = widget.spaceId;
      scheduleMicrotask(() => thumbs.stale(nodeId, spaceId));
    }
    super.dispose();
  }

  Future<void> load() async {
    if (!supported) {
      setState(() => busy = false);
      return;
    }
    setState(() {
      busy = true;
      failed = false;
      notDownloaded = false;
      live = false;
    });
    try {
      if (Platform.isWindows && environment == null) {
        if (await WebViewEnvironment.getAvailableVersion() == null) {
          if (mounted) {
            setState(() {
              busy = false;
              missingRuntime = true;
            });
          }
          return;
        }
        final created = await createSpaceEnvironment(
          storage.file('spaces/browser').path,
        );
        if (!mounted) {
          await created.dispose();
          return;
        }
        environment = created;
        missingRuntime = false;
      }
      var space = current;
      if (!c.connection.ready || c.nodes[widget.nodeId]?.online != true) {
        final previous = await storage.read(cacheKey);
        if (previous == null) {
          if (mounted) {
            setState(() {
              busy = false;
              notDownloaded = true;
            });
          }
          return;
        }
        space = Space.fromJson(previous);
      }
      if (space?.fileId == null) throw StateError('Space has no publication');
      final bytes = await downloadFile(
        c,
        space!.fileId!,
        targetNode: widget.nodeId,
      );
      final next = SpaceBundle(bytes);
      if (!next.files.containsKey('index.html')) {
        throw StateError('Missing index.html');
      }
      await storage.write(cacheKey, space.toJson());
      await c.spaces.sync(widget.nodeId, widget.spaceId);
      if (!mounted || !identical(storage, c.store)) return;
      setState(() {
        loaded = space;
        bundle = next;
        busy = false;
        generation++;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          failed = true;
        });
      }
    }
  }

  void chat({bool edit = false}) {
    final space = current ?? loaded;
    if (space == null) return;
    if (edit) {
      c.spaceDrafts['${widget.nodeId}:${space.conversationId}'] = {
        'spaceId': space.spaceId,
        'name': space.name,
      };
      c.saveContent();
    }
    c.openNotification({
      'nodeId': widget.nodeId,
      'conversationId': space.conversationId,
    });
  }

  Future<void> authorize() async {
    final space = current;
    if (space == null) return;
    final selected = space.allowedOrigins.toSet();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            c.tr('允许此空间访问以下网站？', 'Allow this space to access these websites?'),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final origin in space.origins)
                    CheckboxListTile(
                      value: selected.contains(origin),
                      title: Text(origin),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add(origin);
                        } else {
                          selected.remove(origin);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(c.tr('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(c.tr('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    await action('spaces.authorize', {'origins': selected.toList()});
  }

  Future<void> action(String method, Json params) async {
    try {
      final result = await c.rpc(method, {
        'spaceId': widget.spaceId,
        ...params,
      }, widget.nodeId);
      if (!mounted || !identical(storage, c.store)) return;
      final node = c.nodes[widget.nodeId]!;
      node.spaces[widget.spaceId] = Space.fromJson(result);
      node.notifySnapshot();
      c.saveContent(widget.nodeId);
      if (method == 'spaces.authorize') await load();
      if (params['archived'] == true) chat();
    } catch (_) {
      if (mounted) {
        showNotice(context, c.tr('空间暂时无法打开', 'Unable to open this space'));
      }
    }
  }

  Future<void> menu(String value) async {
    if (value == 'edit') {
      chat(edit: true);
      return;
    }
    if (value == 'access') {
      await authorize();
      return;
    }
    if (value == 'rename') {
      var edited = current?.name ?? '';
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(c.tr('重命名', 'Rename')),
          content: TextFormField(
            initialValue: edited,
            onChanged: (value) => edited = value,
            autofocus: true,
            onFieldSubmitted: (text) => Navigator.pop(context, text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(c.tr('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, edited.trim()),
              child: Text(c.tr('保存', 'Save')),
            ),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) {
        await action('spaces.update', {'name': name});
      }
    } else if (value == 'archive') {
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(c.tr('归档此空间？', 'Archive this space?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(c.tr('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(c.tr('归档', 'Archive')),
            ),
          ],
        ),
      );
      if (yes == true) await action('spaces.update', {'archived': true});
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      c.nodes[widget.nodeId],
      c.spaces,
      c.spaces.thumbs,
    ]),
    builder: (context, _) {
      final space = current ?? loaded;
      final picture = c.spaces.thumbs.picture(widget.nodeId, widget.spaceId);
      final last = picture == null
          ? null
          : SizedBox.expand(
              key: const ValueKey('space-last-picture'),
              child: Image.memory(
                picture,
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                gaplessPlayback: true,
              ),
            );
      final pending = c.spaces
          .data(widget.nodeId, widget.spaceId)
          .pending
          .isNotEmpty;
      final update =
          loaded != null && space != null && loaded!.version < space.version;
      final shown = loaded == null
          ? null
          : Space.fromJson({
              ...loaded!.toJson(),
              'allowedOrigins':
                  (space?.allowedOrigins ?? loaded!.allowedOrigins)
                      .where(loaded!.origins.contains)
                      .toList(),
            });
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          // Beside the rail its bar is as tall as the gallery's, so the
          // space has the room the gallery had.
          toolbarHeight: widget.embedded && !context.tone.glass ? 48 : null,
          leading: IconButton(
            tooltip: c.tr('返回', 'Back'),
            icon: const Icon(Symbols.arrow_back),
            onPressed:
                widget.onBack ??
                (widget.embedded ? chat : () => Navigator.pop(context)),
          ),
          title: Text(
            space?.name ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (pending)
              Tooltip(
                message: c.tr('未同步', 'Not synced'),
                child: const Icon(Symbols.cloud_upload, size: 18),
              ),
            if (update)
              Tooltip(
                message: c.tr('有更新', 'Update available'),
                child: const Icon(Symbols.circle, size: 8),
              ),
            IconAction(
              tooltip: c.tr('刷新', 'Refresh'),
              icon: Symbols.refresh,
              onPressed: busy ? null : load,
            ),
            if (widget.onExpand != null)
              IconAction(
                tooltip: c.tr('展开', 'Expand'),
                icon: widget.expanded
                    ? Symbols.fullscreen_exit
                    : Symbols.fullscreen,
                onPressed: widget.onExpand,
              ),
            ActionMenu<String>(
              key: const ValueKey('space-menu'),
              tooltip: c.tr('更多', 'More'),
              alignEnd: true,
              onSelected: menu,
              items: [
                MenuAction(
                  value: 'edit',
                  icon: Symbols.edit,
                  label: c.tr('请 Dot 修改', 'Edit with Dot'),
                ),
                MenuAction(
                  value: 'access',
                  icon: Symbols.language,
                  label: c.tr('网站访问', 'Website access'),
                ),
                MenuAction(
                  value: 'rename',
                  icon: Symbols.drive_file_rename_outline,
                  label: c.tr('重命名', 'Rename'),
                ),
                null,
                MenuAction(
                  value: 'archive',
                  icon: Symbols.archive,
                  label: c.tr('归档', 'Archive'),
                ),
              ],
            ),
            SizedBox(width: WindowChrome.reserved(context)),
          ],
        ),
        body: !supported
            ? Center(
                child: Text(
                  c.tr('当前设备不支持空间', 'Spaces are not supported on this device'),
                ),
              )
            : missingRuntime
            ? Center(
                child: TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://developer.microsoft.com/microsoft-edge/webview2/',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(c.tr('安装 WebView2', 'Install WebView2')),
                ),
              )
            : busy
            ? SafeArea(
                top: false,
                child: last ?? const Center(child: CircularProgressIndicator()),
              )
            : notDownloaded
            ? Center(child: Text(c.tr('尚未下载', 'Not downloaded')))
            : failed
            ? Center(
                child: TextButton(
                  onPressed: load,
                  child: Text(c.tr('空间暂时无法打开', 'Unable to open this space')),
                ),
              )
            : SafeArea(
                top: false,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SpaceWebView(
                      key: ValueKey(
                        '$generation:${shown!.allowedOrigins.join(',')}',
                      ),
                      client: c,
                      nodeId: widget.nodeId,
                      space: shown,
                      bundle: bundle!,
                      environment: environment,
                      onError: () {
                        if (mounted) setState(() => failed = true);
                      },
                      onDrawn: () => setState(() => live = true),
                    ),
                    // Gone from the tree once the site shows: nothing is left
                    // lying over the web view.
                    IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: Motion.span(context, Motion.swap),
                        child: live || last == null
                            ? const SizedBox.shrink()
                            : last,
                      ),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

/// Creation is a normal chat request. It does not directly publish a package or
/// introduce another agent entry point.
class CreateSpacePage extends StatefulWidget {
  final NekodotClient client;
  final bool compact;
  const CreateSpacePage({
    super.key,
    required this.client,
    this.compact = false,
  });
  @override
  State<CreateSpacePage> createState() => _CreateSpacePageState();
}

class _CreateSpacePageState extends State<CreateSpacePage> {
  final prompt = TextEditingController();
  String? botId;
  bool busy = false;
  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client,
        bots = widget.client.node.bots
            .where((b) => b['archived'] != true)
            .toList();
    final form = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MenuSelect<String>(
            value: botId,
            label: 'Dot',
            options: [
              for (final bot in bots)
                ('${bot['botId']}', '${bot['displayName']}'),
            ],
            leading: (id) => CatAvatar.of(
              bots.firstWhere((bot) => bot['botId'] == id),
              size: 24,
            ),
            onChanged: busy ? null : (value) => setState(() => botId = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: prompt,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: busy || botId == null || prompt.text.trim().isEmpty
                  ? null
                  : () async {
                      final conversation = c.node.conversations.firstWhere(
                        (v) => v['kind'] == 'dm' && v['botId'] == botId,
                      );
                      final id = conversation['conversationId'] as String,
                          nodeId = c.selectedNodeId!;
                      setState(() => busy = true);
                      try {
                        await c.deliveries.enqueue(
                          'messages.send',
                          {
                            'conversationId': id,
                            'text': prompt.text.trim(),
                            'createSpace': true,
                            'clientMsgId': uid(),
                          },
                          nodeId,
                          [],
                        );
                        if (context.mounted) {
                          Navigator.pop(context, conversation);
                        }
                      } catch (_) {
                        if (context.mounted) {
                          setState(() => busy = false);
                          showNotice(
                            context,
                            c.tr('空间暂时无法打开', 'Unable to open this space'),
                          );
                        }
                      }
                    },
              child: Text(c.tr('发送', 'Send')),
            ),
          ),
        ],
      ),
    );
    if (!widget.compact) {
      return Scaffold(
        appBar: AppBar(title: Text(c.tr('新建空间', 'New space'))),
        body: form,
      );
    }
    return Dialog(
      constraints: const BoxConstraints(maxWidth: 480),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.tr('新建空间', 'New space'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: c.tr('关闭', 'Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Symbols.close, size: 18),
                ),
              ],
            ),
          ),
          Flexible(child: form),
        ],
      ),
    );
  }
}
