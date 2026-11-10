part of 'client.dart';

extension ClientContent on NekodotClient {
  Future<Json> continueAction(String method, Json params, [String? nodeId]) {
    if (!const [
      'hermes.settings.set',
      'hermes.shared.set',
      'models.reasoning.set',
      'models.assign',
      'bots.update',
      'groups.update',
      'approvals.respond',
      'questions.respond',
      'runs.stop',
    ].contains(method)) {
      throw ArgumentError('This action cannot be deferred');
    }
    if (method == 'runs.stop' && params['runId'] == null) {
      return Future.value({});
    }
    return deliveries.action(method, params, nodeId ?? selectedNodeId!);
  }

  Future<Json> awaitOperation(Json params, [String? target]) async {
    final token = account.token, nodeId = target ?? selectedNodeId;
    while (!_closed && token != null && token == account.token) {
      try {
        return await connection.rpc('operations.get', params, nodeId);
      } catch (e) {
        if (!isConnectionFailure(e)) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw RelayError('Session ended', 'unauthorized');
  }

  Future<void> restoreContent() async {
    final user = await account.vault.read(
      key: 'content-user:${account.origin}',
    );
    if (user != null && account.token != null) {
      final owner = object(jsonDecode(user));
      if (owner['session'] == account.token) {
        await openContent(owner['userId'] as String);
      }
    }
  }

  Future<void> openContent(String user) async {
    if (_contentUser == user) return;
    final session = account.token;
    final storage = await LocalContent.open('${account.origin}', user);
    final saved = await storage.read('account');
    final restored = <String, NodeData>{};
    for (final item in objects(saved?['me']?['nodes'])) {
      final id = item['nodeId'] as String;
      final snapshot = await storage.read('nodes/$id/index');
      final n = restored[id] = NodeData();
      if (snapshot == null) continue;
      n.snapshot(snapshot);
      n.activities.addAll(
        object(snapshot['activities'] ?? {}).map(
          (id, activity) =>
              MapEntry(id, ConversationActivity.fromJson(object(activity))),
        ),
      );
    }
    final cached = await storage.read('views');
    await reading.load('${account.origin}:$user');
    for (final entry in restored.entries) {
      if (entry.value.seq > 0) {
        await reading.baseline(entry.key, entry.value.seq);
      }
    }
    if (_closed || session == null || session != account.token) {
      for (final n in restored.values) {
        n.dispose();
      }
      return;
    }
    _contentUser = user;
    store = storage;
    nodes.addAll(restored);
    if (saved != null) {
      account.me = object(saved['me']);
      selectedNodeId = saved['selectedNodeId'] as String?;
      workspace.addAll(object(saved['workspace'] ?? {}));
      drafts.addAll(Map<String, String>.from(saved['drafts'] ?? {}));
      quotes.addAll(Map<String, String>.from(saved['quotes'] ?? {}));
      routineDrafts.addAll(
        object(saved['routineDrafts'] ?? {})
            .map((k, v) => MapEntry(k, object(v))),
      );
      attachmentDrafts.addAll(
        object(saved['attachments'] ?? {})
            .map((k, v) => MapEntry(k, objects(v))),
      );
    }
    views.addAll(
      object(cached?['values'] ?? {}).map((k, v) => MapEntry(k, object(v))),
    );
    await deliveries.restore();
  }

  void saveContent([String? nodeId, String? conversation]) {
    if (store == null || _closed) return;
    if (nodeId != null) {
      _dirtyNodes.add(nodeId);
      if (conversation != null) _dirtyMessages.add('$nodeId/$conversation');
    }
    _saveTimer ??= Timer(const Duration(milliseconds: 500), () {
      _saveTimer = null;
      unawaited(
        flushContent().catchError((Object e) {
          error = '$e';
        }),
      );
    });
  }

  Future<void> flushContent() async {
    final storage = store;
    if (storage == null || account.me == null) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    final dirty = Set<String>.of(_dirtyNodes),
        messages = Set<String>.of(_dirtyMessages);
    _dirtyNodes.clear();
    _dirtyMessages.clear();
    final writes = <Future<void>>[];
    // Encode the whole batch before yielding to incoming messages or logout.
    writes.add(
      storage.write('account', {
        'me': account.me,
        'selectedNodeId': selectedNodeId,
        'workspace': workspace,
        'drafts': drafts,
        'quotes': quotes,
        'routineDrafts': routineDrafts,
        'attachments': attachmentDrafts,
      }),
    );
    for (final id in dirty) {
      final n = nodes[id]!;
      writes.add(
        storage.write('nodes/$id/index', {
          'bots': n.bots,
          'groups': n.groups,
          'conversations': n.conversations,
          'latest': n.latest.values.map((m) => m.toJson()).toList(),
          'headSeq': n.seq,
          'node': n.capabilities,
          'flows': n.flows.values.map((f) => f.toJson()).toList(),
          'tasks': n.tasks.values.map((task) => task.toJson()).toList(),
          'taskActivities': n.taskActivities.map(
            (id, activity) => MapEntry(id, activity.toJson()),
          ),
          'activities': n.activities.map(
            (id, activity) => MapEntry(id, activity.toJson()),
          ),
        }),
      );
    }
    for (final key in messages) {
      final split = key.indexOf('/'),
          n = nodes[key.substring(0, key.indexOf('/'))]!;
      writes.add(
        storage.write(
          'nodes/${key.substring(0, split)}/messages/${key.substring(split + 1)}',
          {
            'messages': n.messages[key.substring(split + 1)]!
                .map((m) => m.toJson())
                .toList(),
          },
        ),
      );
    }
    _viewTimer?.cancel();
    _viewTimer = null;
    writes.add(storage.write('views', {'values': views}));
    try {
      await Future.wait(writes);
    } catch (_) {
      if (identical(store, storage)) {
        _dirtyNodes.addAll(dirty);
        _dirtyMessages.addAll(messages);
      }
      rethrow;
    }
  }

  // Explicit product read models only: never persist arbitrary RPC responses.
  static const cachedReads = {
    'tasks.get',
    'tasks.list',
    'routines.list',
    'routines.get',
    'routines.executions',
    'routines.execution',
    'sessions.list',
    'sessions.history',
    'commands.list',
    'files.get',
    'files.list',
    'models.describe',
    'models.reasoning.get',
    'providers.list',
    'models.options',
    'models.info',
    'bots.permissions.get',
    'hermes.settings.get',
    'hermes.shared.get',
    'extensions.list',
    'extensions.content',
    'memory.get',
    'memory.user.get',
    'learning.list',
    'learning.get',
    'operations.get',
    'operations.list',
    'flow.get',
  };
  String viewKey(String method, Json params, String? nodeId) =>
      jsonEncode([nodeId, method, params]);
  Future<Json> readView(String method, Json params, String? nodeId) async {
    final session = account.token;
    final key = viewKey(method, params, nodeId);
    final cached = views[key];
    if ((!connection.ready || nodes[nodeId]?.online != true) &&
        cached != null) {
      return cached;
    }
    try {
      final value = await connection.rpc(method, params, nodeId);
      if (_closed || session != account.token) {
        throw RelayError('Session ended', 'unauthorized');
      }
      views[key] = value;
      _viewTimer ??= Timer(const Duration(milliseconds: 500), () {
        _viewTimer = null;
        unawaited(
          store?.write('views', {'values': views}).catchError((Object e) {
            error = '$e';
          }),
        );
      });
      return value;
    } catch (e) {
      if (cached != null && isConnectionFailure(e)) return cached;
      rethrow;
    }
  }

  bool isConnectionFailure(Object error) => isTransientConnectionError(error);

  Future<Json> statistics(Json filter) async {
    final session = account.token;
    final key = viewKey('usage.query', filter, null);
    if (!connection.ready && views[key] != null) return views[key]!;
    try {
      final result = await account.request(
        '/usage/query',
        method: 'POST',
        body: filter,
      );
      if (_closed || session != account.token) {
        throw RelayError('Session ended', 'unauthorized');
      }
      views[key] = result;
      await store?.write('views', {'values': views});
      return result;
    } catch (e) {
      if (isConnectionFailure(e) && views[key] != null) return views[key]!;
      rethrow;
    }
  }
}
