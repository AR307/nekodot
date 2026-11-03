import 'dart:async';
import 'dart:io';

import '../platform/rust.dart';
import '../screen/bridge/api/process.dart';

/// A hidden child owned by this app; its whole process tree ends with the app.
class OwnedProcess {
  final String id;
  final _lines = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  final List<String> tail = [];
  OwnedProcess._(this.id);

  Stream<String> get lines => _lines.stream;
  Future<int> get exitCode => _exit.future;
  bool get running => !_exit.isCompleted;

  static int _sequence = 0;

  /// [environment] replaces the inherited one entirely.
  static Future<OwnedProcess> start(
    String program,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
    IOSink? log,
  }) async {
    await ensureRust();
    final process = OwnedProcess._('owned-$pid-${_sequence++}');
    ownedProcessRun(
      id: process.id,
      program: program,
      args: arguments,
      cwd: workingDirectory,
      env: [
        for (final entry in environment.entries) '${entry.key}=${entry.value}',
      ],
    ).listen(
      (event) {
        if (event.kind == 1 || event.kind == 2) {
          log?.writeln(event.text);
          process.tail.add(event.text);
          if (process.tail.length > 80) process.tail.removeAt(0);
          process._lines.add(event.text);
        } else {
          if (event.kind == 4) process.tail.add(event.text);
          process._finish(event.kind == 3 ? event.code : -1);
        }
      },
      onError: (Object error) {
        process.tail.add('$error');
        process._finish(-1);
      },
    );
    return process;
  }

  void _finish(int code) {
    if (_exit.isCompleted) return;
    _exit.complete(code);
    unawaited(_lines.close());
  }

  void write(String data, {bool close = false}) {
    if (running) ownedProcessWrite(id: id, data: data, close: close);
  }

  void kill() {
    if (running) ownedProcessKill(id: id);
  }
}

class OwnedResult {
  final int code;
  final List<String> lines;
  const OwnedResult(this.code, this.lines);
  String get output => lines.join('\n');
}

/// Runs a short command to completion without showing a console window.
Future<OwnedResult> runOwned(
  String program,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await OwnedProcess.start(
    program,
    arguments,
    workingDirectory: workingDirectory ?? Directory.systemTemp.path,
    environment: environment ?? Map.of(Platform.environment),
  );
  final lines = <String>[];
  final collected = process.lines.listen(lines.add).asFuture<void>();
  final code = await process.exitCode;
  await collected;
  return OwnedResult(code, lines);
}
