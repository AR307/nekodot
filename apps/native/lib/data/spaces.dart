import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'json.dart';
import 'local_content.dart';

class Space {
  final String spaceId, botId, conversationId, name, createdAt, updatedAt;
  final String? fileId;

  /// The icon its Dot drew for it, as SVG.
  final String? icon;
  final int version;
  final bool archived;
  final List<String> origins, allowedOrigins;
  Space.fromJson(Json value)
    : spaceId = value['spaceId'] as String,
      botId = value['botId'] as String,
      conversationId = value['conversationId'] as String,
      name = value['name'] as String,
      createdAt = value['createdAt'] as String,
      updatedAt = value['updatedAt'] as String,
      fileId = value['fileId'] as String?,
      icon = value['icon'] as String?,
      version = value['version'] as int,
      archived = value['archived'] as bool,
      origins = List<String>.from(value['origins']),
      allowedOrigins = List<String>.from(value['allowedOrigins']);

  Json toJson() => {
    'spaceId': spaceId,
    'botId': botId,
    'conversationId': conversationId,
    'name': name,
    'version': version,
    'fileId': ?fileId,
    'icon': ?icon,
    'archived': archived,
    'origins': origins,
    'allowedOrigins': allowedOrigins,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

class SpaceData {
  final String nodeId, spaceId;
  Json records;
  int revision;
  final List<Json> pending;
  SpaceData(this.nodeId, this.spaceId, Json value)
    : records = object(value['records'] ?? {}),
      revision = value['revision'] as int? ?? 0,
      pending = objects(value['pending']);
  Json toJson() => {
    'nodeId': nodeId,
    'spaceId': spaceId,
    'records': records,
    'revision': revision,
    'pending': pending,
  };
}

/// What each space last looked like on this device: one picture a space,
/// for the gallery and for the moment it opens. It is its own listenable,
/// since a new picture is not a change of records.
class SpaceThumbs extends ChangeNotifier {
  LocalContent? _storage;
  Json _versions = {};
  final _pictures = <String, Uint8List?>{};

  /// Spaces that have been open since their picture was taken: it may no
  /// longer be what they show.
  final _stale = <String>{};

  Future<void> open(LocalContent storage) async {
    final saved = await storage.read('spaces/thumbs');
    _storage = storage;
    _versions = saved ?? {};
    _pictures.clear();
    _stale.clear();
    notifyListeners();
  }

  void close() {
    _storage = null;
    _versions = {};
    _pictures.clear();
    _stale.clear();
  }

  /// The version of the space its picture shows; null with no picture, or
  /// with one that is due again.
  int? version(String nodeId, String spaceId) {
    final key = '$nodeId/$spaceId';
    return _stale.contains(key) ? null : _versions[key] as int?;
  }

  /// The space has been open: its picture is due again. The one kept stays
  /// in place until then.
  void stale(String nodeId, String spaceId) {
    if (_storage != null && _stale.add('$nodeId/$spaceId')) notifyListeners();
  }

  /// The picture, once it has been read. Asking for it is what reads it.
  Uint8List? picture(String nodeId, String spaceId) {
    final key = '$nodeId/$spaceId', storage = _storage;
    if (storage == null || !_versions.containsKey(key)) return null;
    if (!_pictures.containsKey(key)) {
      _pictures[key] = null;
      unawaited(_read(storage, key));
    }
    return _pictures[key];
  }

  Future<void> _read(LocalContent storage, String key) async {
    final bytes = await storage.file('spaces/thumbs/$key.jpg').readAsBytes();
    if (!identical(storage, _storage)) return;
    _pictures[key] = bytes;
    notifyListeners();
  }

  Future<void> keep(
    String nodeId,
    String spaceId,
    int version,
    Uint8List picture,
  ) async {
    final key = '$nodeId/$spaceId', storage = _storage;
    if (storage == null) return;
    final file = storage.file('spaces/thumbs/$key.jpg');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(picture, flush: true);
    if (!identical(storage, _storage)) return;
    _pictures[key] = picture;
    _stale.remove(key);
    // A newer picture of the same version changes nothing in the index.
    if (_versions[key] != version) {
      _versions[key] = version;
      await storage.write('spaces/thumbs', _versions);
    }
    notifyListeners();
  }
}

/// Only record mutations live here. Chat sends and external web requests never
/// enter this queue. The account's LocalContent owns both records and pending IDs.
class SpaceStore extends ChangeNotifier {
  final NekodotClient client;
  SpaceStore(this.client);
  final thumbs = SpaceThumbs();
  LocalContent? _storage;
  final _data = <String, SpaceData>{};
  final _syncing = <String>{};
  Timer? _retry;
  bool _closed = false;

  Future<void> restore() async {
    final storage = client.store;
    if (storage == null) return;
    final saved = await storage.read('spaces/records');
    if (!identical(client.store, storage) || _closed) return;
    _storage = storage;
    _data.clear();
    for (final row in objects(saved?['entries'])) {
      final data = SpaceData(
        row['nodeId'] as String,
        row['spaceId'] as String,
        row,
      );
      _data['${data.nodeId}/${data.spaceId}'] = data;
    }
    await thumbs.open(storage);
  }

  SpaceData data(String nodeId, String spaceId) => _data.putIfAbsent(
    '$nodeId/$spaceId',
    () => SpaceData(nodeId, spaceId, {}),
  );

  Future<void> save() async {
    await _storage?.write('spaces/records', {
      'entries': _data.values.map((d) => d.toJson()).toList(),
    });
  }

  Future<void> set(
    String nodeId,
    String spaceId,
    String key,
    dynamic value,
  ) async {
    if (_storage == null || !identical(_storage, client.store)) {
      throw StateError('Space account is closed');
    }
    final entry = data(nodeId, spaceId);
    entry.records[key] = value;
    entry.pending.add({
      'mutationId': uid(),
      'records': [
        {'key': key, 'value': value},
      ],
    });
    // The bridge acknowledges only after the local record and mutation ID persist.
    await save();
    if (_closed) return;
    notifyListeners();
    unawaited(sync(nodeId, spaceId));
  }

  Future<void> drain() async {
    await Future.wait([
      for (final entry in _data.values.toList())
        sync(entry.nodeId, entry.spaceId),
    ]);
  }

  Future<void> sync(String nodeId, String spaceId) async {
    final storage = _storage, key = '$nodeId/$spaceId';
    if (storage == null ||
        _closed ||
        !client.connection.ready ||
        client.nodes[nodeId]?.online != true ||
        !_syncing.add(key)) {
      return;
    }
    final entry = data(nodeId, spaceId);
    bool current() =>
        !_closed &&
        identical(storage, _storage) &&
        identical(storage, client.store);
    try {
      while (current()) {
        final mutation = entry.pending.firstOrNull;
        final response = await client.rpc(
          mutation == null ? 'spaces.data.read' : 'spaces.data.write',
          {'spaceId': spaceId, ...?mutation},
          nodeId,
        );
        if (!current()) return;
        if (mutation != null) entry.pending.remove(mutation);
        if ((response['revision'] as int) >= entry.revision) {
          entry.revision = response['revision'] as int;
          entry.records = {
            for (final record in objects(response['records']))
              record['key'] as String: record['value'],
          };
          for (final pending in entry.pending) {
            for (final record in objects(pending['records'])) {
              entry.records[record['key'] as String] = record['value'];
            }
          }
        }
        await save();
        if (current()) notifyListeners();
        if (entry.pending.isEmpty) break;
      }
    } catch (error) {
      // Keep accepted local changes visible; retry storage only after transport
      // recovery. A failed write never becomes a new model or website request.
      if (current() &&
          client.isConnectionFailure(error) &&
          entry.pending.isNotEmpty) {
        _retry ??= Timer(const Duration(seconds: 5), () {
          _retry = null;
          unawaited(drain());
        });
      }
    } finally {
      _syncing.remove(key);
    }
  }

  void changed(String nodeId, String spaceId) {
    if (_data.containsKey('$nodeId/$spaceId')) unawaited(sync(nodeId, spaceId));
  }

  Future<void> suspend() async {
    _retry?.cancel();
    _retry = null;
    await save();
    _storage = null;
    _data.clear();
    thumbs.close();
  }

  @override
  void dispose() {
    _closed = true;
    _retry?.cancel();
    thumbs.dispose();
    super.dispose();
  }
}
