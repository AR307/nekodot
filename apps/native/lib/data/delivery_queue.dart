import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

import 'account.dart';
import 'client.dart';
import 'json.dart';

/// Only user-confirmed chat submissions; never a retry wrapper for arbitrary RPC.
class DeliveryQueue extends ChangeNotifier {
  final NekodotClient client;
  final List<Json> items = [];
  final Set<String> _busy = {};
  Timer? _retry;
  int _generation = 0;
  bool _closed = false;
  final _responses = <String, Completer<Json>>{};
  DeliveryQueue(this.client);
  Future<void> restore() async {
    final generation = _generation, storage = client.store;
    final saved = await storage?.read('deliveries');
    if (_closed || generation != _generation || client.store != storage) return;
    items.clear();
    items.addAll(objects(saved?['items']));
    for (final item in items) {
      if (item['state'] == 'sending') item['state'] = 'queued';
      if (item['state'] == 'observing') item['state'] = 'completed';
    }
    notifyListeners();
  }

  Future<void> save() async {
    await client.store?.write('deliveries', {'items': items});
    if (!_closed) notifyListeners();
  }

  Future<Json> enqueue(
    String method,
    Json params,
    String nodeId,
    List<Json> attachments,
  ) async {
    if (client.store == null) {
      throw StateError('Local account storage is not ready');
    }
    final id = params['clientMsgId'] as String;
    final item = <String, dynamic>{
      'id': id,
      'nodeId': nodeId,
      'method': method,
      'params': params,
      'files': attachments,
      'state': 'queued',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    items.add(item);
    try {
      await save();
    } catch (_) {
      items.remove(item);
      rethrow;
    }
    unawaited(drain());
    return item;
  }

  Future<Json> action(String method, Json params, String nodeId) async {
    final id = uid(), response = Completer<Json>();
    _responses[id] = response;
    items.add({
      'id': id,
      'nodeId': nodeId,
      'method': method,
      'params': params,
      'state': 'queued',
      'action': true,
    });
    try {
      await save();
    } catch (_) {
      items.removeWhere((i) => i['id'] == id);
      _responses.remove(id);
      rethrow;
    }
    unawaited(drain());
    return response.future;
  }

  Future<void> cancel(String id) async {
    final item = items.where((i) => i['id'] == id).firstOrNull;
    if (item == null ||
        item['state'] == 'sending' ||
        (item['submitted'] == true && item['state'] != 'failed')) {
      return;
    }
    items.remove(item);
    await save();
    unawaited(drain());
  }

  Future<Json> command(Json params, String nodeId) async {
    final id = params['clientMsgId'] as String;
    final response = Completer<Json>();
    _responses[id] = response;
    try {
      await enqueue('commands.execute', params, nodeId, []);
    } catch (_) {
      _responses.remove(id);
      rethrow;
    }
    return response.future;
  }

  String _key(Json item) => item['action'] == true
      ? '${item['nodeId']}:action:${item['id']}'
      : '${item['nodeId']}:${item['params']['conversationId']}';

  Future<void> drain() async {
    if (_closed || !client.connection.ready || client.account.token == null) {
      return;
    }
    final keys = items
        .where((i) => ['queued', 'accepted'].contains(i['state']))
        .map(_key)
        .toSet();
    await Future.wait(keys.map(_drainConversation));
  }

  Future<void> _drainConversation(String key) async {
    if (!_busy.add(key)) return;
    final generation = _generation;
    try {
      while (!_closed && generation == _generation && client.connection.ready) {
        final item = items
            .where(
              (i) =>
                  _key(i) == key &&
                  ['queued', 'accepted', 'failed'].contains(i['state']),
            )
            .firstOrNull;
        if (item == null ||
            item['state'] == 'failed' ||
            client.nodes[item['nodeId']]?.online != true) {
          break;
        }
        try {
          final params = object(item['params']);
          Json? result = item['result'] == null ? null : object(item['result']);
          if (result == null) {
            item['state'] = 'sending';
            await save();
            final files = <String>[];
            final uploadFiles = objects(item['files']);
            item['files'] = uploadFiles;
            for (final file in uploadFiles) {
              files.add(
                await upload(
                  file,
                  item['nodeId'] as String,
                  params['conversationId'] as String,
                ),
              );
              if (generation != _generation) return;
              await save();
            }
            if (files.isNotEmpty) params['files'] = files;
            if (generation != _generation) return;
            if (item['method'] == 'messages.send') {
              final existing = client
                  .nodes[item['nodeId']]
                  ?.messages[params['conversationId']]
                  ?.where((m) => m.clientMsgId == item['id'])
                  .firstOrNull;
              if (existing != null) {
                items.remove(item);
                await save();
                continue;
              }
            }
            if (item['method'] == 'hermes.settings.set') {
              final actual = await client.connection.rpc(
                'hermes.settings.get',
                {'botId': params['botId']},
                item['nodeId'] as String,
              );
              final field = objects(actual['fields'])
                  .where((f) => f['key'] == params['key'])
                  .firstOrNull;
              if (field != null &&
                  const DeepCollectionEquality().equals(
                    field['value'],
                    params['value'],
                  )) {
                result = {'key': params['key'], 'saved': true};
              }
            }
            if (item['method'] == 'bots.update' ||
                item['method'] == 'groups.update') {
              final group = item['method'] == 'groups.update';
              final snapshot = await client.connection.rpc(
                'sync.snapshot',
                {},
                item['nodeId'] as String,
              );
              final key = group ? 'groupId' : 'botId';
              final actual = objects(snapshot[group ? 'groups' : 'bots'])
                  .where((row) => row[key] == params[key])
                  .firstOrNull;
              if (actual != null) {
                final compared = <String, dynamic>{...actual};
                if (params.containsKey('approvalMode')) {
                  compared['approvalMode'] = (await client.connection.rpc(
                    'bots.permissions.get',
                    {'botId': params['botId']},
                    item['nodeId'] as String,
                  ))['mode'];
                }
                if (params.entries.every(
                  (entry) => const DeepCollectionEquality().equals(
                    compared[entry.key],
                    entry.value,
                  ),
                )) {
                  result = {group ? 'group' : 'bot': actual};
                }
              }
            }
            if (item['method'] == 'models.assign') {
              final settings = await client.connection.rpc(
                'hermes.settings.get',
                {'botId': params['botId']},
                item['nodeId'] as String,
              );
              final sources = await client.connection.rpc(
                'providers.list',
                {},
                item['nodeId'] as String,
              );
              final source = objects(sources['sources'])
                  .where((row) => row['sourceId'] == params['sourceId'])
                  .firstOrNull;
              final values = {
                for (final field in objects(settings['fields']))
                  field['key']: field['value'],
              };
              final providerKey = params['key'] == 'cron.model'
                  ? 'cron.model_provider'
                  : '${params['key']}'.replaceFirst(
                      RegExp(r'\.model$'),
                      '.provider',
                    );
              if (source != null &&
                  values[params['key']] == params['model'] &&
                  values[providerKey] == source['provider']) {
                result = {'saved': true};
              }
            }
            if (item['method'] == 'models.reasoning.set') {
              final actual = await client.connection.rpc(
                'models.reasoning.get',
                {'botId': params['botId']},
                item['nodeId'] as String,
              );
              if (actual['sessionId'] == params['sessionId'] &&
                  actual['effort'] == params['effort']) {
                result = actual;
              }
            }
            if (generation != _generation) return;
            item['submitted'] = true;
            await save();
            if (generation != _generation) return;
            result ??= await client.connection.rpc(
              item['method'] as String,
              params,
              item['nodeId'] as String,
            );
            if (generation != _generation) return;
            if (item['method'] == 'commands.execute') {
              item['result'] = result;
              item['state'] = 'accepted';
            }
            await save();
          }
          if (item['method'] == 'commands.execute') {
            var operation = result;
            while (operation['status'] == 'running' &&
                generation == _generation) {
              await Future<void>.delayed(const Duration(milliseconds: 500));
              operation = await client.awaitOperation({
                'operationId': operation['operationId'],
              }, item['nodeId'] as String);
            }
            if (generation != _generation) return;
            item['result'] = operation;
            if (operation['status'] != 'done') {
              item['state'] = 'failed';
              item['error'] = operation['detail'];
              _responses
                  .remove(item['id'])
                  ?.completeError(RelayError('${operation['detail']}'));
              await save();
              break;
            }
            item['state'] = 'completed';
            result = operation;
            if (_responses.containsKey(item['id'])) items.remove(item);
          } else {
            items.remove(item);
          }
          _responses.remove(item['id'])?.complete(result);
          await save();
          if (params['conversationId'] != null) {
            unawaited(
              client
                  .loadMessages(
                    params['conversationId'] as String,
                    target: item['nodeId'] as String,
                  )
                  .catchError((Object _) {}),
            );
          }
        } catch (e) {
          if (generation != _generation) return;
          final transient = client.isConnectionFailure(e);
          if (e is RelayError && e.code == 'node_offline') {
            item['submitted'] = false;
          }
          item['state'] = transient
              ? (item['result'] != null ? 'accepted' : 'queued')
              : 'failed';
          if (!transient) {
            item['error'] = '$e';
            if (item['action'] == true && !_responses.containsKey(item['id'])) {
              client.reportError('$e');
            }
          }
          if (!transient) _responses.remove(item['id'])?.completeError(e);
          await save();
          if (transient) {
            _retry?.cancel();
            _retry = Timer(
              const Duration(seconds: 2),
              () => unawaited(drain()),
            );
          }
          break;
        }
      }
    } finally {
      _busy.remove(key);
    }
  }

  Future<String> upload(Json file, String nodeId, String conversationId) async {
    final generation = _generation, token = client.account.token;
    if (file['fileId'] != null) return file['fileId'] as String;
    if (file['importId'] == null) {
      file['importId'] = (await client.connection.rpc(
        'imports.create',
        {},
        nodeId,
      ))['importId'];
      await save();
    }
    final source = File(file['localPath'] as String);
    final handle = await source.open();
    try {
      var offset = (file['offset'] as int?) ?? 0;
      final size = await source.length();
      await handle.setPosition(offset);
      while (offset < size || (size == 0 && file['offset'] == null)) {
        if (generation != _generation) {
          throw RelayError('Session ended', 'unauthorized');
        }
        final bytes = await handle.read(196608);
        final response = await client.account.transport
            .put(
              client.account
                  .url('/api/nodes/$nodeId/imports/${file['importId']}')
                  .replace(
                    queryParameters: {
                      'path': '${file['name']}',
                      'offset': '$offset',
                    },
                  ),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/octet-stream',
              },
              body: bytes,
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw RelayError(
            'Upload HTTP ${response.statusCode}',
            response.statusCode == 503 ? 'unavailable' : '',
            response.statusCode,
          );
        }
        offset += bytes.length;
        file['offset'] = offset;
        await save();
        if (bytes.isEmpty || offset >= await source.length()) break;
      }
    } finally {
      await handle.close();
    }
    if (generation != _generation) {
      throw RelayError('Session ended', 'unauthorized');
    }
    final result = await client.connection.rpc('files.receive', {
      'conversationId': conversationId,
      'importId': file['importId'],
      'path': file['name'],
    }, nodeId);
    file['fileId'] = result['fileId'];
    return result['fileId'] as String;
  }

  void suspend() {
    _generation++;
    _retry?.cancel();
    items.clear();
    for (final response in _responses.values) {
      response.completeError(RelayError('Session ended', 'unauthorized'));
    }
    _responses.clear();
  }

  @override
  void dispose() {
    _closed = true;
    suspend();
    super.dispose();
  }
}
